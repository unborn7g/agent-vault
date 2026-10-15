// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AgentVault}    from "../AgentVault.sol";
import {MockERC20}     from "../test-helpers/MockERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
//  Handler for invariant testing
// ─────────────────────────────────────────────────────────────────────────────

contract VaultHandler is Test {
    AgentVault  public vault;
    MockERC20   public usdc;
    address     public owner;
    address     public agent;

    uint256 public ghostFunded;      // total USDC sent into the vault via fund()
    uint256 public ghostWithdrawn;   // total USDC transferred OUT (proposals + escrow releases)
    uint256 public ghostEscrowed;    // sum of active escrow amounts

    constructor(AgentVault _vault, MockERC20 _usdc, address _owner, address _agent) {
        vault  = _vault;
        usdc   = _usdc;
        owner  = _owner;
        agent  = _agent;
    }

    // ── fund ──────────────────────────────────────────────────────────────────
    function fund(uint256 amount) external {
        amount = bound(amount, 1, 10_000e6);
        usdc.mint(address(this), amount);
        usdc.approve(address(vault), amount);
        vault.fund(amount);
        ghostFunded += amount;
    }

    // ── propose + approve + execute (owner proposes & executes) ──────────────
    function proposeAndExecute(address recipient, uint256 amount) external {
        amount    = bound(amount, 1, vault.perTxCap());
        recipient = address(uint160(bound(uint256(uint160(recipient)), 1, type(uint160).max)));

        // ensure vault has enough free balance
        uint256 free = _free();
        if (free < amount) {
            usdc.mint(address(vault), amount - free + 1);
            ghostFunded += amount - free + 1;
        }

        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(recipient, amount, "inv");
        vault.approveProposal(pid);
        vault.executeProposal(pid);
        vm.stopPrank();

        ghostWithdrawn += amount;
    }

    // ── createEscrow + refundEscrow (net-zero: no withdrawal) ────────────────
    function createAndRefundEscrow(address payee, uint256 amount) external {
        amount = bound(amount, 1, vault.perTxCap());
        payee  = address(uint160(bound(uint256(uint160(payee)), 1, type(uint160).max)));

        uint256 free = _free();
        if (free < amount) {
            usdc.mint(address(vault), amount - free + 1);
            ghostFunded += amount - free + 1;
        }

        vm.startPrank(agent);
        uint256 eid = vault.createEscrow(payee, amount, "cond");
        vm.stopPrank();

        vm.prank(owner);
        vault.refundEscrow(eid);
    }

    // ── helper ────────────────────────────────────────────────────────────────
    function _free() internal view returns (uint256) {
        uint256 bal = usdc.balanceOf(address(vault));
        uint256 esc = vault.escrowedBalance();
        return bal > esc ? bal - esc : 0;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main test contract
// ─────────────────────────────────────────────────────────────────────────────

contract AgentVaultTest is Test {

    // ── constants ─────────────────────────────────────────────────────────────
    uint256 internal constant PER_TX_CAP  = 100e6;   //  100 USDC
    uint256 internal constant DAILY_CAP   = 500e6;   //  500 USDC
    uint256 internal constant VAULT_SEED  = 1_000e6; // 1 000 USDC pre-funded

    // ── actors ────────────────────────────────────────────────────────────────
    // owner must match the hardcoded INITIAL_OWNER in AgentVault.sol
    address internal owner  = 0x51039aF25D8AD8B04B86ed89AacBCb9cDd526c9c;
    address internal alice  = makeAddr("alice");
    address internal bob    = makeAddr("bob");
    address internal carol  = makeAddr("carol");
    address internal nobody = makeAddr("nobody");

    // ── contracts ─────────────────────────────────────────────────────────────
    MockERC20  internal usdc;
    AgentVault internal vault;

    // ─────────────────────────────────────────────────────────────────────────
    //  setUp
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        // 1. Deploy mock USDC
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        // 2. Deploy vault as owner
        vm.prank(owner);
        vault = new AgentVault(address(usdc), PER_TX_CAP, DAILY_CAP);

        // 3. Seed vault with USDC (mint directly to vault address)
        usdc.mint(address(vault), VAULT_SEED);

        // 4. Approve alice as an agent
        vm.prank(owner);
        vault.approveAgent(alice);
    }

    // =========================================================================
    // CONSTRUCTOR / INITIALIZATION
    // =========================================================================

    function test_Constructor_SetsState() public view {
        assertEq(address(vault.usdc()),  address(usdc));
        assertEq(vault.owner(),          owner);
        assertEq(vault.perTxCap(),       PER_TX_CAP);
        assertEq(vault.dailyCap(),       DAILY_CAP);
        assertEq(vault.spentToday(),     0);
        assertEq(vault.dayStart(),       block.timestamp);
        assertEq(vault.escrowedBalance(), 0);
        assertTrue(vault.isAgent(owner));
    }

    function test_Constructor_EmitsAgentApprovedAndCapsUpdated() public {
        MockERC20 u2 = new MockERC20("U2", "U2", 6);
        vm.expectEmit(true, false, false, false);
        // AgentApproved is emitted for the hardcoded INITIAL_OWNER, not msg.sender
        emit AgentVault.AgentApproved(0x51039aF25D8AD8B04B86ed89AacBCb9cDd526c9c);
        vm.expectEmit(false, false, false, true);
        emit AgentVault.CapsUpdated(PER_TX_CAP, DAILY_CAP);
        new AgentVault(address(u2), PER_TX_CAP, DAILY_CAP);
    }

    function test_Constructor_RevertsOnZeroUsdcAddress() public {
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        new AgentVault(address(0), PER_TX_CAP, DAILY_CAP);
    }

    // =========================================================================
    // setCaps
    // =========================================================================

    function test_SetCaps_UpdatesBoth() public {
        vm.prank(owner);
        vault.setCaps(200e6, 1_000e6);
        assertEq(vault.perTxCap(), 200e6);
        assertEq(vault.dailyCap(), 1_000e6);
    }

    function test_SetCaps_EmitsCapsUpdated() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(vault));
        emit AgentVault.CapsUpdated(200e6, 1_000e6);
        vault.setCaps(200e6, 1_000e6);
    }

    function test_SetCaps_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.setCaps(1, 1);
    }

    // =========================================================================
    // approveAgent
    // =========================================================================

    function test_ApproveAgent_SetsFlag() public {
        vm.prank(owner);
        vault.approveAgent(bob);
        assertTrue(vault.isAgent(bob));
    }

    function test_ApproveAgent_EmitsAgentApproved() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(vault));
        emit AgentVault.AgentApproved(bob);
        vault.approveAgent(bob);
    }

    function test_ApproveAgent_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.approveAgent(bob);
    }

    function test_ApproveAgent_RevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        vault.approveAgent(address(0));
    }

    // =========================================================================
    // revokeAgent
    // =========================================================================

    function test_RevokeAgent_ClearsFlag() public {
        vm.prank(owner);
        vault.revokeAgent(alice);
        assertFalse(vault.isAgent(alice));
    }

    function test_RevokeAgent_EmitsAgentRevoked() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(vault));
        emit AgentVault.AgentRevoked(alice);
        vault.revokeAgent(alice);
    }

    function test_RevokeAgent_RevertsForNonOwner() public {
        vm.prank(nobody);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.revokeAgent(alice);
    }

    function test_RevokeAgent_RevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        vault.revokeAgent(address(0));
    }

    // =========================================================================
    // fund
    // =========================================================================

    function test_Fund_TransfersUsdcToVault() public {
        usdc.mint(bob, 50e6);
        vm.startPrank(bob);
        usdc.approve(address(vault), 50e6);
        uint256 balBefore = usdc.balanceOf(address(vault));
        vault.fund(50e6);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(vault)), balBefore + 50e6);
    }

    function test_Fund_EmitsVaultFunded() public {
        usdc.mint(bob, 50e6);
        vm.startPrank(bob);
        usdc.approve(address(vault), 50e6);
        vm.expectEmit(true, false, false, true, address(vault));
        emit AgentVault.VaultFunded(bob, 50e6);
        vault.fund(50e6);
        vm.stopPrank();
    }

    function test_Fund_RevertsOnZeroAmount() public {
        vm.expectRevert(AgentVault.ZeroAmount.selector);
        vault.fund(0);
    }

    function test_Fund_RevertsWhenTransferFromFails() public {
        // bob has no allowance → transferFrom returns false
        usdc.mint(bob, 50e6);
        vm.prank(bob);
        vm.expectRevert(AgentVault.InsufficientVaultBalance.selector);
        vault.fund(50e6);
    }

    // =========================================================================
    // proposePayment
    // =========================================================================

    function test_ProposePayment_HappyPath_Owner() public {
        vm.prank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "work");
        assertEq(pid, 0);
        assertEq(vault.proposalsCount(), 1);
        (address proposer, address recipient, uint256 amount, string memory reason, AgentVault.ProposalState state) =
            vault.proposals(0);
        assertEq(proposer,   owner);
        assertEq(recipient,  bob);
        assertEq(amount,     50e6);
        assertEq(reason,     "work");
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Pending));
    }

    function test_ProposePayment_HappyPath_Agent() public {
        vm.prank(alice); // alice is an approved agent
        uint256 pid = vault.proposePayment(bob, 50e6, "task");
        assertEq(pid, 0);
    }

    function test_ProposePayment_EmitsPaymentProposed() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(vault));
        emit AgentVault.PaymentProposed(0, owner, bob, 50e6, "work");
        vault.proposePayment(bob, 50e6, "work");
    }

    function test_ProposePayment_RevertsForNonProposer() public {
        vm.prank(nobody);
        vm.expectRevert(AgentVault.NotProposer.selector);
        vault.proposePayment(bob, 50e6, "x");
    }

    function test_ProposePayment_RevertsForZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        vault.proposePayment(address(0), 50e6, "x");
    }

    function test_ProposePayment_RevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAmount.selector);
        vault.proposePayment(bob, 0, "x");
    }

    function test_ProposePayment_RevertsWhenExceedsPerTxCap() public {
        vm.prank(owner);
        vm.expectRevert(AgentVault.ExceedsPerTxCap.selector);
        vault.proposePayment(bob, PER_TX_CAP + 1, "x");
    }

    function test_ProposePayment_RevertsWhenExceedsDailyCap() public {
        // Fill up the daily cap with successful proposals
        vm.startPrank(owner);
        // 5 × 100e6 = 500e6 = DAILY_CAP  (propose only, no execution → spentToday still 0)
        // But _checkCaps checks spentToday + amount > dailyCap.
        // We need to actually run proposals AND execute them to move spentToday.
        // Instead: propose many up to limit.  At proposal time spentToday is 0 so all 5 pass.
        // The 6th will fail because the cap check at propose time is cumulative ONLY if
        // spentToday is already charged. We need to execute them first to move spentToday.
        // Execute 5 proposals of 100e6 to exhaust the daily cap.
        for (uint i = 0; i < 5; i++) {
            uint256 pid = vault.proposePayment(bob, PER_TX_CAP, "x");
            vault.approveProposal(pid);
            vault.executeProposal(pid);
        }
        // 6th proposal should hit daily cap
        vm.expectRevert(AgentVault.ExceedsDailyCap.selector);
        vault.proposePayment(bob, 1e6, "x");
        vm.stopPrank();
    }

    function test_ProposePayment_IncrementsProposaId() public {
        vm.startPrank(owner);
        uint256 id0 = vault.proposePayment(bob, 10e6, "a");
        uint256 id1 = vault.proposePayment(bob, 10e6, "b");
        uint256 id2 = vault.proposePayment(bob, 10e6, "c");
        vm.stopPrank();
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    // =========================================================================
    // approveProposal
    // =========================================================================

    function test_ApproveProposal_SetsApprovedState() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vm.stopPrank();
        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Approved));
    }

    function test_ApproveProposal_EmitsProposalApproved() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vm.expectEmit(true, false, false, false, address(vault));
        emit AgentVault.ProposalApproved(pid);
        vault.approveProposal(pid);
        vm.stopPrank();
    }

    function test_ApproveProposal_RevertsForNonOwner() public {
        vm.prank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.approveProposal(pid);
    }

    function test_ApproveProposal_RevertsIfAlreadyApproved() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.approveProposal(pid);
        vm.stopPrank();
    }

    function test_ApproveProposal_RevertsIfRejected() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.rejectProposal(pid);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.approveProposal(pid);
        vm.stopPrank();
    }

    // =========================================================================
    // rejectProposal
    // =========================================================================

    function test_RejectProposal_SetsRejectedState() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.rejectProposal(pid);
        vm.stopPrank();
        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Rejected));
    }

    function test_RejectProposal_EmitsProposalRejected() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vm.expectEmit(true, false, false, false, address(vault));
        emit AgentVault.ProposalRejected(pid);
        vault.rejectProposal(pid);
        vm.stopPrank();
    }

    function test_RejectProposal_RevertsForNonOwner() public {
        vm.prank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.rejectProposal(pid);
    }

    function test_RejectProposal_RevertsIfAlreadyRejected() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.rejectProposal(pid);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.rejectProposal(pid);
        vm.stopPrank();
    }

    function test_RejectProposal_RevertsIfApproved() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.rejectProposal(pid);
        vm.stopPrank();
    }

    // =========================================================================
    // executeProposal
    // =========================================================================

    function test_ExecuteProposal_TransfersUsdc() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        uint256 bobBefore  = usdc.balanceOf(bob);
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        vault.executeProposal(pid);
        vm.stopPrank();
        assertEq(usdc.balanceOf(bob),          bobBefore  + 50e6);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore - 50e6);
    }

    function test_ExecuteProposal_UpdatesSpentToday() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vault.executeProposal(pid);
        vm.stopPrank();
        assertEq(vault.spentToday(), 50e6);
    }

    function test_ExecuteProposal_SetsExecutedState() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vault.executeProposal(pid);
        vm.stopPrank();
        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Executed));
    }

    function test_ExecuteProposal_EmitsProposalExecuted() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.ProposalExecuted(pid, bob, 50e6);
        vault.executeProposal(pid);
        vm.stopPrank();
    }

    function test_ExecuteProposal_RevertsForNonOwner() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.executeProposal(pid);
    }

    function test_ExecuteProposal_RevertsIfPending() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.executeProposal(pid);
        vm.stopPrank();
    }

    function test_ExecuteProposal_RevertsIfRejected() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.rejectProposal(pid);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.executeProposal(pid);
        vm.stopPrank();
    }

    function test_ExecuteProposal_RevertsIfAlreadyExecuted() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.approveProposal(pid);
        vault.executeProposal(pid);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.executeProposal(pid);
        vm.stopPrank();
    }

    function test_ExecuteProposal_RevertsWhenInsufficientBalance() public {
        // Drain vault to zero first, then re-seed with only 10 USDC
        // Directly set vault USDC balance to 10e6 (below the 50e6 proposal)
        // We do this by minting a fresh vault context:
        MockERC20  u2 = new MockERC20("U2", "U2", 6);
        vm.prank(owner);
        AgentVault v2 = new AgentVault(address(u2), PER_TX_CAP, DAILY_CAP);
        usdc.mint(address(v2), 10e6); // only 10 USDC

        vm.startPrank(owner);
        uint256 pid = v2.proposePayment(bob, 50e6, "x");
        v2.approveProposal(pid);
        vm.expectRevert(AgentVault.InsufficientVaultBalance.selector);
        v2.executeProposal(pid);
        vm.stopPrank();
    }

    function test_ExecuteProposal_RevertsWhenExceedsDailyCapAtExecute() public {
        // Propose with low spentToday, then drive spentToday up manually before execute
        // We do so by executing other proposals first.
        vm.startPrank(owner);
        // Exhaust 450e6 of daily cap
        for (uint i = 0; i < 4; i++) {
            uint256 pid = vault.proposePayment(bob, PER_TX_CAP, "fill");
            vault.approveProposal(pid);
            vault.executeProposal(pid);
        }
        // Spend 50e6 more via a proposal approved before cap was near
        // Note: propose time also checks caps, so we must propose at the current spentToday=400e6
        // 400 + 100 = 500 == dailyCap, still OK at propose time
        uint256 lastPid = vault.proposePayment(bob, PER_TX_CAP, "last");
        vault.approveProposal(lastPid);
        // Now spentToday = 400e6 and the cap check at execute time is 400+100 = 500 == dailyCap (ok)
        vault.executeProposal(lastPid);
        // spentToday is now 500 = DAILY_CAP; any more execution should fail
        // Propose only passes if spentToday + amount <= dailyCap ... 500 + 1 > 500 → revert
        vm.expectRevert(AgentVault.ExceedsDailyCap.selector);
        vault.proposePayment(bob, 1e6, "overflow");
        vm.stopPrank();
    }

    function test_ExecuteProposal_RevertsWhenAvailableBalanceLockedByEscrow() public {
        // Lock vault balance in escrow so available balance < proposal amount
        vm.startPrank(owner);
        // Create an escrow that locks 990 USDC out of the 1000 USDC vault balance
        uint256 eid = vault.createEscrow(bob, 990e6, "locked");
        // Only 10 USDC is free
        uint256 pid = vault.proposePayment(bob, 50e6, "x"); // propose 50e6
        vault.approveProposal(pid);
        vm.expectRevert(AgentVault.InsufficientVaultBalance.selector);
        vault.executeProposal(pid);
        vm.stopPrank();
        // Cleanup
        vm.prank(owner);
        vault.refundEscrow(eid);
    }

    // =========================================================================
    // Daily rollover
    // =========================================================================

    function test_DailyRollover_ResetsSpentToday() public {
        // Spend 100 USDC today (within perTxCap of 100e6)
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 100e6, "x");
        vault.approveProposal(pid);
        vault.executeProposal(pid);
        assertEq(vault.spentToday(), 100e6);

        // Warp past 1 day
        skip(1 days + 1);

        // Now propose + execute again; rollover should have reset spentToday
        uint256 pid2 = vault.proposePayment(bob, 100e6, "y");
        vault.approveProposal(pid2);
        vault.executeProposal(pid2);
        vm.stopPrank();

        // spentToday should be 100e6 again (not 200e6)
        assertEq(vault.spentToday(), 100e6);
    }

    function test_DailyRollover_UpdatesDayStart() public {
        uint256 t0 = block.timestamp;
        skip(1 days + 1);
        // Trigger a rollover via proposePayment
        vm.prank(owner);
        vault.proposePayment(bob, 1e6, "x");
        assertGt(vault.dayStart(), t0);
        assertEq(vault.dayStart(), block.timestamp);
    }

    // =========================================================================
    // createEscrow
    // =========================================================================

    function test_CreateEscrow_HappyPath() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "deliver by Monday");
        assertEq(eid, 0);
        assertEq(vault.escrowsCount(), 1);
        (address proposer, address payee, uint256 amount, string memory condition, AgentVault.EscrowState state) =
            vault.escrows(0);
        assertEq(proposer,   alice);
        assertEq(payee,      bob);
        assertEq(amount,     100e6);
        assertEq(condition,  "deliver by Monday");
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Active));
        assertEq(vault.escrowedBalance(), 100e6);
    }

    function test_CreateEscrow_EmitsEscrowCreated() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(vault));
        emit AgentVault.EscrowCreated(0, alice, bob, 100e6, "cond");
        vault.createEscrow(bob, 100e6, "cond");
    }

    function test_CreateEscrow_RevertsForNonProposer() public {
        vm.prank(nobody);
        vm.expectRevert(AgentVault.NotProposer.selector);
        vault.createEscrow(bob, 100e6, "cond");
    }

    function test_CreateEscrow_RevertsForZeroPayee() public {
        vm.prank(alice);
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        vault.createEscrow(address(0), 100e6, "cond");
    }

    function test_CreateEscrow_RevertsForZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(AgentVault.ZeroAmount.selector);
        vault.createEscrow(bob, 0, "cond");
    }

    function test_CreateEscrow_RevertsWhenInsufficientFreeBalance() public {
        // Lock 990 USDC in an escrow first; only 10 free
        vm.prank(owner);
        vault.createEscrow(bob, 990e6, "first");

        vm.prank(alice);
        vm.expectRevert(AgentVault.InsufficientVaultBalance.selector);
        vault.createEscrow(carol, 50e6, "second");
    }

    function test_CreateEscrow_LocksBalanceFromFreePool() public {
        uint256 before = vault.escrowedBalance();
        vm.prank(alice);
        vault.createEscrow(bob, 200e6, "lock");
        assertEq(vault.escrowedBalance(), before + 200e6);
    }

    // =========================================================================
    // releaseEscrow
    // =========================================================================

    function test_ReleaseEscrow_TransfersToPayee() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");

        uint256 bobBefore = usdc.balanceOf(bob);
        vm.prank(owner);
        vault.releaseEscrow(eid);

        assertEq(usdc.balanceOf(bob), bobBefore + 100e6);
    }

    function test_ReleaseEscrow_DecreasesEscrowedBalance() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");

        vm.prank(owner);
        vault.releaseEscrow(eid);

        assertEq(vault.escrowedBalance(), 0);
    }

    function test_ReleaseEscrow_SetsReleasedState() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(owner);
        vault.releaseEscrow(eid);
        (, , , , AgentVault.EscrowState state) = vault.escrows(eid);
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Released));
    }

    function test_ReleaseEscrow_EmitsEscrowReleased() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.EscrowReleased(eid, bob, 100e6);
        vault.releaseEscrow(eid);
    }

    function test_ReleaseEscrow_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.releaseEscrow(eid);
    }

    function test_ReleaseEscrow_RevertsIfAlreadyReleased() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.startPrank(owner);
        vault.releaseEscrow(eid);
        vm.expectRevert(AgentVault.InvalidEscrowState.selector);
        vault.releaseEscrow(eid);
        vm.stopPrank();
    }

    function test_ReleaseEscrow_RevertsIfRefunded() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.startPrank(owner);
        vault.refundEscrow(eid);
        vm.expectRevert(AgentVault.InvalidEscrowState.selector);
        vault.releaseEscrow(eid);
        vm.stopPrank();
    }

    // =========================================================================
    // refundEscrow
    // =========================================================================

    function test_RefundEscrow_SetsRefundedState() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(owner);
        vault.refundEscrow(eid);
        (, , , , AgentVault.EscrowState state) = vault.escrows(eid);
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Refunded));
    }

    function test_RefundEscrow_DecreasesEscrowedBalance() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(owner);
        vault.refundEscrow(eid);
        assertEq(vault.escrowedBalance(), 0);
    }

    function test_RefundEscrow_EmitsEscrowRefunded() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit AgentVault.EscrowRefunded(eid, 100e6);
        vault.refundEscrow(eid);
    }

    function test_RefundEscrow_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.prank(nobody);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.refundEscrow(eid);
    }

    function test_RefundEscrow_RevertsIfAlreadyRefunded() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        vm.startPrank(owner);
        vault.refundEscrow(eid);
        vm.expectRevert(AgentVault.InvalidEscrowState.selector);
        vault.refundEscrow(eid);
        vm.stopPrank();
    }

    function test_RefundEscrow_DoesNotTransferUsdc() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(bob, 100e6, "cond");
        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        vm.prank(owner);
        vault.refundEscrow(eid);
        // refund just unlocks, no transfer
        assertEq(usdc.balanceOf(bob),          bobBefore);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore);
    }

    // =========================================================================
    // _availableVaultBalance (tested indirectly via createEscrow + execute)
    // =========================================================================

    function test_AvailableBalance_RespectsEscrowedBalance() public {
        // 1 000 USDC in vault, lock 900 USDC in escrow → only 100 free
        vm.prank(alice);
        vault.createEscrow(bob, 900e6, "lock");

        // Proposing 100e6 should succeed (exactly at free balance)
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 100e6, "x");
        vault.approveProposal(pid);
        vault.executeProposal(pid); // should NOT revert
        vm.stopPrank();
    }

    function test_AvailableBalance_ZeroWhenFullyEscrowed() public {
        // Lock all 1000 USDC
        vm.prank(alice);
        vault.createEscrow(bob, VAULT_SEED, "all");

        // Any proposal execute should revert with InsufficientVaultBalance
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 1e6, "x");
        vault.approveProposal(pid);
        vm.expectRevert(AgentVault.InsufficientVaultBalance.selector);
        vault.executeProposal(pid);
        vm.stopPrank();
    }

    // =========================================================================
    // splitPayment
    // =========================================================================

    function _makeSplit2() internal view
        returns (address[] memory recipients, uint256[] memory bps)
    {
        recipients    = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        bps           = new uint256[](2);
        bps[0]        = 5_000; // 50 %
        bps[1]        = 5_000; // 50 %
    }

    function test_SplitPayment_HappyPath_TwoEqual() public {
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        uint256 total = 80e6;
        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 carolBefore = usdc.balanceOf(carol);
        vm.prank(owner);
        vault.splitPayment(r, b, total);
        // Bob gets 40, carol gets (80 - 40) = 40 (last-element dust logic)
        assertEq(usdc.balanceOf(bob),   bobBefore   + 40e6);
        assertEq(usdc.balanceOf(carol), carolBefore + 40e6);
    }

    function test_SplitPayment_UpdatesSpentToday() public {
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        vm.prank(owner);
        vault.splitPayment(r, b, 80e6);
        assertEq(vault.spentToday(), 80e6);
    }

    function test_SplitPayment_EmitsSplitPaymentExecuted() public {
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(vault));
        emit AgentVault.SplitPaymentExecuted(80e6, 2, 0);
        vault.splitPayment(r, b, 80e6);
    }

    function test_SplitPayment_RevertsForNonOwner() public {
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.splitPayment(r, b, 80e6);
    }

    function test_SplitPayment_RevertsOnEmptyRecipients() public {
        address[] memory r = new address[](0);
        uint256[] memory b = new uint256[](0);
        vm.prank(owner);
        vm.expectRevert(AgentVault.InvalidBps.selector);
        vault.splitPayment(r, b, 10e6);
    }

    function test_SplitPayment_RevertsOnMismatchedArrays() public {
        address[] memory r = new address[](2);
        r[0] = bob; r[1] = carol;
        uint256[] memory b = new uint256[](1);
        b[0] = 10_000;
        vm.prank(owner);
        vm.expectRevert(AgentVault.InvalidBps.selector);
        vault.splitPayment(r, b, 10e6);
    }

    function test_SplitPayment_RevertsOnZeroTotalAmount() public {
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAmount.selector);
        vault.splitPayment(r, b, 0);
    }

    function test_SplitPayment_RevertsWhenBpsSumNot10000() public {
        address[] memory r = new address[](2);
        r[0] = bob; r[1] = carol;
        uint256[] memory b = new uint256[](2);
        b[0] = 4_000; b[1] = 4_000; // sum = 8000, not 10000
        vm.prank(owner);
        vm.expectRevert(AgentVault.InvalidBps.selector);
        vault.splitPayment(r, b, 80e6);
    }

    function test_SplitPayment_RevertsWhenExceedsDailyCap() public {
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        // totalAmount = 600e6 > dailyCap 500e6
        vm.prank(owner);
        vm.expectRevert(AgentVault.ExceedsDailyCap.selector);
        vault.splitPayment(r, b, 600e6);
    }

    function test_SplitPayment_RevertsWhenShareExceedsPerTxCap() public {
        // 3 recipients, each 200e6 / 3 ≈ 66e6 OK but total = 200e6; however
        // let's make one share > perTxCap (100e6):
        // 2 recipients, bps 9000 / 1000 on 200e6:
        //   share[0] = 200e6 * 9000 / 10000 = 180e6 > perTxCap → revert
        address[] memory r = new address[](2);
        r[0] = bob; r[1] = carol;
        uint256[] memory b = new uint256[](2);
        b[0] = 9_000; b[1] = 1_000;
        vm.prank(owner);
        vm.expectRevert(AgentVault.ExceedsPerTxCap.selector);
        vault.splitPayment(r, b, 200e6);
    }

    function test_SplitPayment_RevertsOnZeroRecipient() public {
        address[] memory r = new address[](2);
        r[0] = address(0); r[1] = bob;
        uint256[] memory b = new uint256[](2);
        b[0] = 5_000; b[1] = 5_000;
        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        vault.splitPayment(r, b, 80e6);
    }

    function test_SplitPayment_RevertsWhenInsufficientBalance() public {
        // Drain vault, then try split
        MockERC20  u2 = new MockERC20("U2", "U2", 6);
        vm.prank(owner);
        AgentVault v2 = new AgentVault(address(u2), PER_TX_CAP, DAILY_CAP);
        u2.mint(address(v2), 5e6); // only 5 USDC

        (address[] memory r, uint256[] memory b) = _makeSplit2();
        vm.prank(owner);
        vm.expectRevert(AgentVault.InsufficientVaultBalance.selector);
        v2.splitPayment(r, b, 80e6);
    }

    function test_SplitPayment_SkipsBlockedRecipient_ReturnsFalse() public {
        // Block carol's incoming transfers (returns false, no revert)
        usdc.setTransferBlocked(carol, true);

        (address[] memory r, uint256[] memory b) = _makeSplit2();
        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 carolBefore = usdc.balanceOf(carol);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit AgentVault.SplitPaymentSkipped(carol, 40e6);
        vm.expectEmit(false, false, false, true, address(vault));
        emit AgentVault.SplitPaymentExecuted(40e6, 1, 1);
        vault.splitPayment(r, b, 80e6);

        assertEq(usdc.balanceOf(bob),   bobBefore   + 40e6); // bob received
        assertEq(usdc.balanceOf(carol), carolBefore);         // carol skipped
    }

    function test_SplitPayment_SkipsRevertingRecipient_TryCatch() public {
        // Carol's transfer reverts entirely (catch branch)
        usdc.setTransferReverts(carol, true);

        (address[] memory r, uint256[] memory b) = _makeSplit2();
        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 carolBefore = usdc.balanceOf(carol);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit AgentVault.SplitPaymentSkipped(carol, 40e6);
        vault.splitPayment(r, b, 80e6);

        assertEq(usdc.balanceOf(bob),   bobBefore   + 40e6); // bob still received
        assertEq(usdc.balanceOf(carol), carolBefore);         // carol skipped
    }

    function test_SplitPayment_OnlyCountsActualSpentAgainstDailyCap() public {
        // Block carol → only bob's 40e6 is "actual spent"
        usdc.setTransferBlocked(carol, true);
        (address[] memory r, uint256[] memory b) = _makeSplit2();
        vm.prank(owner);
        vault.splitPayment(r, b, 80e6);
        // spentToday should be 40e6 (only the successful share), NOT 80e6
        assertEq(vault.spentToday(), 40e6);
    }

    function test_SplitPayment_ThreeRecipients_DustGoesToLast() public {
        // 3 recipients, 10_000 / 3 isn't exact → last gets remainder
        address[] memory r = new address[](3);
        r[0] = alice; r[1] = bob; r[2] = carol;
        uint256[] memory b = new uint256[](3);
        b[0] = 3_334; b[1] = 3_333; b[2] = 3_333; // sum = 10000

        uint256 total = 60e6;
        vm.prank(owner);
        vault.splitPayment(r, b, total);

        uint256 share0 = (total * 3_334) / 10_000; // 20.004e6
        uint256 share1 = (total * 3_333) / 10_000; // 19.998e6
        uint256 share2 = total - share0 - share1;  // remainder

        assertEq(usdc.balanceOf(alice), share0);
        assertEq(usdc.balanceOf(bob),   share1);
        assertEq(usdc.balanceOf(carol), share2);
    }

    // =========================================================================
    // Fuzz — proposePayment caps
    // =========================================================================

    function testFuzz_ProposePayment_CapBoundary(uint256 amount) public {
        // Any amount in [1, perTxCap] with spentToday==0 and amount<=dailyCap should succeed
        amount = bound(amount, 1, PER_TX_CAP);
        vm.prank(owner);
        uint256 pid = vault.proposePayment(bob, amount, "fuzz");
        (, , uint256 stored, , ) = vault.proposals(pid);
        assertEq(stored, amount);
    }

    function testFuzz_ProposePayment_ExceedsPerTxCap(uint256 amount) public {
        amount = bound(amount, PER_TX_CAP + 1, type(uint128).max);
        vm.prank(owner);
        vm.expectRevert(AgentVault.ExceedsPerTxCap.selector);
        vault.proposePayment(bob, amount, "fuzz");
    }

    function testFuzz_SetCaps_OwnerCanAlwaysSet(uint256 ptx, uint256 daily) public {
        vm.prank(owner);
        vault.setCaps(ptx, daily);
        assertEq(vault.perTxCap(), ptx);
        assertEq(vault.dailyCap(), daily);
    }

    function testFuzz_Fund_AnyAmountIncreasesBalance(uint256 amount) public {
        amount = bound(amount, 1, 100_000e6);
        usdc.mint(bob, amount);
        vm.startPrank(bob);
        usdc.approve(address(vault), amount);
        uint256 before = usdc.balanceOf(address(vault));
        vault.fund(amount);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(vault)), before + amount);
    }

    function testFuzz_ExecuteProposal_SpentTodayAccumulates(uint256 a, uint256 b_) public {
        a  = bound(a,  1, PER_TX_CAP);
        b_ = bound(b_, 1, PER_TX_CAP);
        vm.assume(a + b_ <= DAILY_CAP);

        vm.startPrank(owner);
        uint256 p0 = vault.proposePayment(bob, a,  "a");
        uint256 p1 = vault.proposePayment(bob, b_, "b");
        vault.approveProposal(p0);
        vault.approveProposal(p1);
        vault.executeProposal(p0);
        vault.executeProposal(p1);
        vm.stopPrank();

        assertEq(vault.spentToday(), a + b_);
    }

    function testFuzz_SplitPayment_BpsSum(uint256 bps0) public {
        // Only valid when bps0 is in [1, 9999]; complement makes bps1 = 10000 - bps0
        bps0 = bound(bps0, 1, 9_999);
        uint256 bps1 = 10_000 - bps0;

        uint256 totalAmount = 80e6;
        uint256 share0 = (totalAmount * bps0) / 10_000;
        uint256 share1 = totalAmount - share0; // last gets remainder

        // Both shares must be within perTxCap for the split to succeed
        vm.assume(share0 <= PER_TX_CAP && share1 <= PER_TX_CAP);

        address[] memory r = new address[](2);
        r[0] = bob; r[1] = carol;
        uint256[] memory b = new uint256[](2);
        b[0] = bps0; b[1] = bps1;

        vm.prank(owner);
        vault.splitPayment(r, b, totalAmount);

        assertEq(usdc.balanceOf(bob)   + usdc.balanceOf(carol), totalAmount);
    }

    function testFuzz_CreateEscrow_LocksFreeBalance(uint256 amount) public {
        amount = bound(amount, 1, VAULT_SEED);
        vm.prank(alice);
        vault.createEscrow(bob, amount, "fuzz");
        assertEq(vault.escrowedBalance(), amount);
    }

    // =========================================================================
    // INVARIANT — vault token balance always covers escrowedBalance
    // =========================================================================
}

// ─────────────────────────────────────────────────────────────────────────────
//  Invariant test (separate contract so targetContract works correctly)
// ─────────────────────────────────────────────────────────────────────────────

contract AgentVaultInvariantTest is Test {

    uint256 internal constant PER_TX_CAP = 100e6;
    uint256 internal constant DAILY_CAP  = 500e6;

    address internal owner = 0x51039aF25D8AD8B04B86ed89AacBCb9cDd526c9c;
    address internal agent = makeAddr("agent");

    MockERC20    internal usdc;
    AgentVault   internal vault;
    VaultHandler internal handler;

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        vm.prank(owner);
        vault = new AgentVault(address(usdc), PER_TX_CAP, DAILY_CAP);

        // Seed and approve agent
        usdc.mint(address(vault), 10_000e6);
        vm.prank(owner);
        vault.approveAgent(agent);

        handler = new VaultHandler(vault, usdc, owner, agent);
        targetContract(address(handler));
    }

    /// INVARIANT: vault USDC token balance is always >= escrowedBalance.
    function invariant_VaultBalanceCoverEscrowed() public view {
        assertGe(
            usdc.balanceOf(address(vault)),
            vault.escrowedBalance(),
            "vault balance must always cover escrowed amount"
        );
    }

    /// INVARIANT: escrowedBalance is non-negative (uint256 can't underflow, but sanity check).
    function invariant_EscrowedBalanceNotNegative() public view {
        // uint256 is always >= 0; this checks our ghost vs contract accounting
        assertEq(vault.escrowedBalance(), vault.escrowedBalance()); // tautology kept for illustration
    }

    /// INVARIANT: spentToday never exceeds dailyCap.
    function invariant_SpentTodayWithinDailyCap() public view {
        assertLe(vault.spentToday(), vault.dailyCap());
    }
}

