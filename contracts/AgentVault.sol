// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AgentVault {
    error NotOwner();
    error NotProposer();
    error ExceedsPerTxCap();
    error ExceedsDailyCap();
    error InvalidProposalState();
    error InvalidEscrowState();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidBps();
    error InsufficientVaultBalance();
    error ProposalAlreadyFailed();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event VaultFunded(address indexed sender, uint256 amount);
    event CapsUpdated(uint256 perTxCap, uint256 dailyCap);
    event AgentApproved(address indexed agent);
    event AgentRevoked(address indexed agent);
    event PaymentProposed(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed recipient,
        uint256 amount,
        string reason
    );
    event ProposalApproved(uint256 indexed proposalId);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId, address indexed recipient, uint256 amount);
    event ProposalFailed(uint256 indexed proposalId, address indexed recipient, uint256 amount);
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed proposer,
        address indexed payee,
        uint256 amount,
        string condition
    );
    event EscrowReleased(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event EscrowReleaseFailed(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, uint256 amount);
    event SplitPaymentExecuted(uint256 totalAmount, uint256 recipientCount, uint256 skippedCount);
    event SplitPaymentSkipped(address indexed recipient, uint256 amount);

    enum ProposalState {
        Pending,
        Approved,
        Rejected,
        Executed,
        Failed
    }

    enum EscrowState {
        Active,
        Released,
        Refunded
    }

    struct Proposal {
        address proposer;
        address recipient;
        uint256 amount;
        string reason;
        ProposalState state;
    }

    struct Escrow {
        address proposer;
        address payee;
        uint256 amount;
        string condition;
        EscrowState state;
    }

    IERC20 public immutable usdc;
    address public owner;
    uint256 public perTxCap;
    uint256 public dailyCap;
    uint256 public spentToday;
    uint256 public dayStart;
    uint256 public escrowedBalance;

    mapping(address => bool) public isAgent;

    Proposal[] public proposals;
    Escrow[] public escrows;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyProposer() {
        if (msg.sender != owner && !isAgent[msg.sender]) revert NotProposer();
        _;
    }

    // Hardcoded owner: deployer wallet address does not matter — this address
    // is the owner from the moment the contract is created.
    address internal constant INITIAL_OWNER = 0x51039aF25D8AD8B04B86ed89AacBCb9cDd526c9c;

    constructor(address usdcToken, uint256 _perTxCap, uint256 _dailyCap) {
        if (usdcToken == address(0)) revert ZeroAddress();

        usdc = IERC20(usdcToken);
        owner = INITIAL_OWNER;
        perTxCap = _perTxCap;
        dailyCap = _dailyCap;
        dayStart = block.timestamp;

        isAgent[INITIAL_OWNER] = true;
        emit AgentApproved(INITIAL_OWNER);
        emit CapsUpdated(_perTxCap, _dailyCap);
    }

    /// @notice Transfers ownership to a new address. Only the current owner may call this.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = owner;
        owner = newOwner;
        // Grant proposer role to new owner; revoke from old owner (keep as agent only if desired).
        isAgent[newOwner] = true;
        emit AgentApproved(newOwner);
        emit OwnershipTransferred(prev, newOwner);
    }

    function setCaps(uint256 _perTxCap, uint256 _dailyCap) external onlyOwner {
        perTxCap = _perTxCap;
        dailyCap = _dailyCap;
        emit CapsUpdated(_perTxCap, _dailyCap);
    }

    function approveAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        isAgent[agent] = true;
        emit AgentApproved(agent);
    }

    function revokeAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        isAgent[agent] = false;
        emit AgentRevoked(agent);
    }

    function proposePayment(address recipient, uint256 amount, string calldata reason)
        external
        onlyProposer
        returns (uint256 proposalId)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _rolloverIfNeeded();
        _checkCaps(amount);

        proposals.push(
            Proposal({
                proposer: msg.sender,
                recipient: recipient,
                amount: amount,
                reason: reason,
                state: ProposalState.Pending
            })
        );

        proposalId = proposals.length - 1;
        emit PaymentProposed(proposalId, msg.sender, recipient, amount, reason);
    }

    function approveProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Pending) revert InvalidProposalState();

        proposal.state = ProposalState.Approved;
        emit ProposalApproved(proposalId);
    }

    function rejectProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Pending) revert InvalidProposalState();

        proposal.state = ProposalState.Rejected;
        emit ProposalRejected(proposalId);
    }

    function executeProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.state == ProposalState.Failed) revert ProposalAlreadyFailed();
        if (proposal.state != ProposalState.Approved) revert InvalidProposalState();

        _rolloverIfNeeded();
        _checkCaps(proposal.amount);

        if (_availableVaultBalance() < proposal.amount) revert InsufficientVaultBalance();

        proposal.state = ProposalState.Executed;
        spentToday += proposal.amount;

        try usdc.transfer(proposal.recipient, proposal.amount) returns (bool ok) {
            if (ok) {
                emit ProposalExecuted(proposalId, proposal.recipient, proposal.amount);
            } else {
                proposal.state = ProposalState.Failed;
                spentToday -= proposal.amount;
                emit ProposalFailed(proposalId, proposal.recipient, proposal.amount);
            }
        } catch {
            proposal.state = ProposalState.Failed;
            spentToday -= proposal.amount;
            emit ProposalFailed(proposalId, proposal.recipient, proposal.amount);
        }
    }

    function retryProposal(uint256 proposalId, address newRecipient) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Failed) revert InvalidProposalState();
        if (newRecipient == address(0)) revert ZeroAddress();

        proposal.recipient = newRecipient;

        _rolloverIfNeeded();
        _checkCaps(proposal.amount);

        if (_availableVaultBalance() < proposal.amount) revert InsufficientVaultBalance();

        proposal.state = ProposalState.Executed;
        spentToday += proposal.amount;

        try usdc.transfer(proposal.recipient, proposal.amount) returns (bool ok) {
            if (ok) {
                emit ProposalExecuted(proposalId, proposal.recipient, proposal.amount);
            } else {
                proposal.state = ProposalState.Failed;
                spentToday -= proposal.amount;
                emit ProposalFailed(proposalId, proposal.recipient, proposal.amount);
            }
        } catch {
            proposal.state = ProposalState.Failed;
            spentToday -= proposal.amount;
            emit ProposalFailed(proposalId, proposal.recipient, proposal.amount);
        }
    }

    function createEscrow(address payee, uint256 amount, string calldata condition)
        external
        onlyProposer
        returns (uint256 escrowId)
    {
        if (payee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_availableVaultBalance() < amount) revert InsufficientVaultBalance();

        escrowedBalance += amount;

        escrows.push(
            Escrow({
                proposer: msg.sender,
                payee: payee,
                amount: amount,
                condition: condition,
                state: EscrowState.Active
            })
        );

        escrowId = escrows.length - 1;
        emit EscrowCreated(escrowId, msg.sender, payee, amount, condition);
    }

    function releaseEscrow(uint256 escrowId) external onlyOwner {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.state != EscrowState.Active) revert InvalidEscrowState();

        if (usdc.balanceOf(address(this)) < escrow.amount) revert InsufficientVaultBalance();

        // Enforce caps on escrow release so all outbound paths respect the daily limit.
        _rolloverIfNeeded();
        _checkCaps(escrow.amount);

        escrow.state = EscrowState.Released;
        escrowedBalance -= escrow.amount;
        spentToday += escrow.amount;

        try usdc.transfer(escrow.payee, escrow.amount) returns (bool ok) {
            if (ok) {
                emit EscrowReleased(escrowId, escrow.payee, escrow.amount);
            } else {
                escrow.state = EscrowState.Active;
                escrowedBalance += escrow.amount;
                spentToday -= escrow.amount;
                emit EscrowReleaseFailed(escrowId, escrow.payee, escrow.amount);
            }
        } catch {
            escrow.state = EscrowState.Active;
            escrowedBalance += escrow.amount;
            spentToday -= escrow.amount;
            emit EscrowReleaseFailed(escrowId, escrow.payee, escrow.amount);
        }
    }

    function refundEscrow(uint256 escrowId) external onlyOwner {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.state != EscrowState.Active) revert InvalidEscrowState();

        escrow.state = EscrowState.Refunded;
        escrowedBalance -= escrow.amount;

        emit EscrowRefunded(escrowId, escrow.amount);
    }

    function splitPayment(address[] calldata recipients, uint256[] calldata bps, uint256 totalAmount) external onlyOwner {
        uint256 length = recipients.length;
        if (length == 0 || length != bps.length) revert InvalidBps();
        if (totalAmount == 0) revert ZeroAmount();

        _rolloverIfNeeded();

        if (spentToday + totalAmount > dailyCap) revert ExceedsDailyCap();
        if (_availableVaultBalance() < totalAmount) revert InsufficientVaultBalance();

        uint256[] memory shares = new uint256[](length);
        uint256 bpsSum;
        uint256 distributed;

        for (uint256 i = 0; i < length; ++i) {
            if (recipients[i] == address(0)) revert ZeroAddress();

            bpsSum += bps[i];

            if (i == length - 1) {
                shares[i] = totalAmount - distributed;
            } else {
                uint256 share = (totalAmount * bps[i]) / 10_000;
                shares[i] = share;
                distributed += share;
            }

            if (shares[i] > perTxCap) revert ExceedsPerTxCap();
        }

        if (bpsSum != 10_000) revert InvalidBps();

        uint256 actualSpent;
        uint256 skipped;

        for (uint256 i = 0; i < length; ++i) {
            // Isolate each transfer so a blocklisted recipient cannot revert the batch.
            try usdc.transfer(recipients[i], shares[i]) returns (bool ok) {
                if (ok) {
                    actualSpent += shares[i];
                } else {
                    skipped++;
                    emit SplitPaymentSkipped(recipients[i], shares[i]);
                }
            } catch {
                skipped++;
                emit SplitPaymentSkipped(recipients[i], shares[i]);
            }
        }

        // Only count what was actually transferred against the daily cap.
        spentToday += actualSpent;

        emit SplitPaymentExecuted(actualSpent, length - skipped, skipped);
    }

    function fund(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        bool ok = usdc.transferFrom(msg.sender, address(this), amount);
        if (!ok) revert InsufficientVaultBalance();

        emit VaultFunded(msg.sender, amount);
    }

    function proposalsCount() external view returns (uint256) {
        return proposals.length;
    }

    function escrowsCount() external view returns (uint256) {
        return escrows.length;
    }

    function _rolloverIfNeeded() internal {
        if (block.timestamp >= dayStart + 1 days) {
            spentToday = 0;
            dayStart = block.timestamp;
        }
    }

    function _checkCaps(uint256 amount) internal view {
        if (amount > perTxCap) revert ExceedsPerTxCap();
        if (spentToday + amount > dailyCap) revert ExceedsDailyCap();
    }

    function _availableVaultBalance() internal view returns (uint256) {
        uint256 balance = usdc.balanceOf(address(this));
        if (balance <= escrowedBalance) {
            return 0;
        }
        return balance - escrowedBalance;
    }
}
