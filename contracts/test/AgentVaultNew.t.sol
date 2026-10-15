// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AgentVault}    from "../AgentVault.sol";
import {MockERC20}     from "../test-helpers/MockERC20.sol";

// =============================================================================
//  New-feature tests added for the updated AgentVault contract:
//
//  1. executeProposal try/catch — transfer returns false → Failed, decrements
//     spentToday, emits ProposalFailed, does NOT revert
//  2. executeProposal try/catch — transfer reverts → same as (1)
//  3. retryProposal happy path — Failed → re-executes, updates spentToday,
//     emits ProposalExecuted
//  4. retryProposal — reverts when state != Failed
//  5. retryProposal — reverts when newRecipient == address(0)
//  6. retryProposal — new recipient also blocked → emits ProposalFailed again,
//     stays Failed
//  7. releaseEscrow try/catch — transfer returns false → state stays Active,
//     escrowedBalance restored, emits EscrowReleaseFailed, no revert
//  8. releaseEscrow try/catch — transfer reverts → same as (7)
// =============================================================================

contract AgentVaultNewTest is Test {

    // ── constants ─────────────────────────────────────────────────────────────
    uint256 internal constant PER_TX_CAP = 100e6;
    uint256 internal constant DAILY_CAP  = 500e6;
    uint256 internal constant VAULT_SEED = 1_000e6;

    // ── actors ────────────────────────────────────────────────────────────────
    // owner must match the hardcoded INITIAL_OWNER in AgentVault.sol
    address internal owner  = 0x51039aF25D8AD8B04B86ed89AacBCb9cDd526c9c;
    address internal alice  = makeAddr("alice");   // approved agent
    address internal bob    = makeAddr("bob");     // normal recipient
    address internal carol  = makeAddr("carol");   // "blocked" / "reverting" recipient

    // ── contracts ─────────────────────────────────────────────────────────────
    MockERC20  internal usdc;
    AgentVault internal vault;

    // ─────────────────────────────────────────────────────────────────────────
    //  setUp — fresh state before every test
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        vm.prank(owner);
        vault = new AgentVault(address(usdc), PER_TX_CAP, DAILY_CAP);

        // Seed vault with 1 000 USDC directly (no approval needed)
        usdc.mint(address(vault), VAULT_SEED);

        // Approve alice as an agent
        vm.prank(owner);
        vault.approveAgent(alice);
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// Propose → approve a payment, return proposalId.  Does NOT execute.
    function _proposeAndApprove(address recipient, uint256 amount)
        internal returns (uint256 pid)
    {
        vm.startPrank(owner);
        pid = vault.proposePayment(recipient, amount, "test");
        vault.approveProposal(pid);
        vm.stopPrank();
    }

    /// Drive a proposal to the Failed state via a blocked transfer.
    function _driveToFailed(address recipient, uint256 amount)
        internal returns (uint256 pid)
    {
        // Block the recipient so transfer() returns false.
        usdc.setTransferBlocked(recipient, true);
        pid = _proposeAndApprove(recipient, amount);
        vm.prank(owner);
        vault.executeProposal(pid);          // should succeed but land in Failed
        usdc.setTransferBlocked(recipient, false); // clear for subsequent calls
    }

    /// Drive a proposal to the Failed state via a reverting transfer.
    function _driveToFailedViaRevert(address recipient, uint256 amount)
        internal returns (uint256 pid)
    {
        usdc.setTransferReverts(recipient, true);
        pid = _proposeAndApprove(recipient, amount);
        vm.prank(owner);
        vault.executeProposal(pid);
        usdc.setTransferReverts(recipient, false);
    }

    // =========================================================================
    //  1. executeProposal — transfer returns false → Failed, no revert
    // =========================================================================

    /// After executeProposal when transfer returns false, state must be Failed.
    function test_ExecuteProposal_TransferReturnsFalse_SetsFailedState() public {
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vault.executeProposal(pid);  // must NOT revert

        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Failed));
    }

    /// spentToday must be decremented back to its pre-execute value when transfer
    /// returns false (i.e., the cap is not permanently consumed).
    function test_ExecuteProposal_TransferReturnsFalse_DecrementsSpentToday() public {
        uint256 spentBefore = vault.spentToday();
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vault.executeProposal(pid);

        assertEq(vault.spentToday(), spentBefore,
            "spentToday should be restored on failed transfer");
    }

    /// ProposalFailed must be emitted (not ProposalExecuted) when transfer returns false.
    function test_ExecuteProposal_TransferReturnsFalse_EmitsProposalFailed() public {
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.ProposalFailed(pid, carol, 50e6);
        vault.executeProposal(pid);
    }

    /// Vault USDC balance must remain unchanged when the transfer returns false
    /// (the tokens were never actually moved).
    function test_ExecuteProposal_TransferReturnsFalse_VaultBalanceUnchanged() public {
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vault.executeProposal(pid);

        assertEq(usdc.balanceOf(address(vault)), vaultBefore,
            "vault balance must not change when transfer returns false");
    }

    // =========================================================================
    //  2. executeProposal — transfer reverts → Failed, no revert (catch branch)
    // =========================================================================

    /// After executeProposal when transfer reverts, state must be Failed.
    function test_ExecuteProposal_TransferReverts_SetsFailedState() public {
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vault.executeProposal(pid);  // must NOT propagate the revert

        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Failed));
    }

    /// spentToday must be decremented back when the inner transfer reverts.
    function test_ExecuteProposal_TransferReverts_DecrementsSpentToday() public {
        uint256 spentBefore = vault.spentToday();
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vault.executeProposal(pid);

        assertEq(vault.spentToday(), spentBefore,
            "spentToday should be restored on reverting transfer");
    }

    /// ProposalFailed emitted (catch branch).
    function test_ExecuteProposal_TransferReverts_EmitsProposalFailed() public {
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.ProposalFailed(pid, carol, 50e6);
        vault.executeProposal(pid);
    }

    /// Vault balance must be unchanged when the inner transfer reverts.
    function test_ExecuteProposal_TransferReverts_VaultBalanceUnchanged() public {
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        uint256 pid = _proposeAndApprove(carol, 50e6);
        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vault.executeProposal(pid);

        assertEq(usdc.balanceOf(address(vault)), vaultBefore);
    }

    // =========================================================================
    //  3. retryProposal — happy path
    //     (Failed → new recipient succeeds → Executed, spentToday updated,
    //      ProposalExecuted emitted)
    // =========================================================================

    /// After a successful retry the proposal state must be Executed.
    function test_RetryProposal_HappyPath_SetsExecutedState() public {
        uint256 pid = _driveToFailed(carol, 50e6);

        vm.prank(owner);
        vault.retryProposal(pid, bob);  // bob is not blocked

        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Executed));
    }

    /// The new recipient stored on the proposal must be updated.
    function test_RetryProposal_HappyPath_UpdatesRecipient() public {
        uint256 pid = _driveToFailed(carol, 50e6);

        vm.prank(owner);
        vault.retryProposal(pid, bob);

        (, address recipient, , , ) = vault.proposals(pid);
        assertEq(recipient, bob, "proposal recipient should be updated to newRecipient");
    }

    /// spentToday must be incremented by the proposal amount after a successful retry.
    function test_RetryProposal_HappyPath_UpdatesSpentToday() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        uint256 spentAfterFail = vault.spentToday(); // should be 0 (decremented during fail)

        vm.prank(owner);
        vault.retryProposal(pid, bob);

        assertEq(vault.spentToday(), spentAfterFail + 50e6,
            "spentToday should increase by proposal.amount on successful retry");
    }

    /// USDC must actually land in the new recipient's wallet.
    function test_RetryProposal_HappyPath_TransfersUsdc() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        uint256 bobBefore = usdc.balanceOf(bob);

        vm.prank(owner);
        vault.retryProposal(pid, bob);

        assertEq(usdc.balanceOf(bob), bobBefore + 50e6,
            "new recipient should receive USDC on successful retry");
    }

    /// ProposalExecuted must be emitted with the new recipient.
    function test_RetryProposal_HappyPath_EmitsProposalExecuted() public {
        uint256 pid = _driveToFailed(carol, 50e6);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.ProposalExecuted(pid, bob, 50e6);
        vault.retryProposal(pid, bob);
    }

    /// Only the owner may call retryProposal.
    function test_RetryProposal_RevertsForNonOwner() public {
        uint256 pid = _driveToFailed(carol, 50e6);

        vm.prank(alice);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.retryProposal(pid, bob);
    }

    // =========================================================================
    //  4. retryProposal — reverts when state != Failed
    // =========================================================================

    /// Retry on a Pending proposal → InvalidProposalState.
    function test_RetryProposal_RevertsWhenPending() public {
        vm.prank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");

        vm.prank(owner);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.retryProposal(pid, bob);
    }

    /// Retry on an Approved proposal → InvalidProposalState.
    function test_RetryProposal_RevertsWhenApproved() public {
        uint256 pid = _proposeAndApprove(bob, 50e6);

        vm.prank(owner);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.retryProposal(pid, bob);
    }

    /// Retry on a successfully Executed proposal → InvalidProposalState.
    function test_RetryProposal_RevertsWhenExecuted() public {
        uint256 pid = _proposeAndApprove(bob, 50e6);
        vm.prank(owner);
        vault.executeProposal(pid);   // succeeds → Executed

        vm.prank(owner);
        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.retryProposal(pid, bob);
    }

    /// Retry on a Rejected proposal → InvalidProposalState.
    function test_RetryProposal_RevertsWhenRejected() public {
        vm.startPrank(owner);
        uint256 pid = vault.proposePayment(bob, 50e6, "x");
        vault.rejectProposal(pid);

        vm.expectRevert(AgentVault.InvalidProposalState.selector);
        vault.retryProposal(pid, bob);
        vm.stopPrank();
    }

    // =========================================================================
    //  5. retryProposal — reverts when newRecipient == address(0)
    // =========================================================================

    function test_RetryProposal_RevertsOnZeroNewRecipient() public {
        uint256 pid = _driveToFailed(carol, 50e6);

        vm.prank(owner);
        vm.expectRevert(AgentVault.ZeroAddress.selector);
        vault.retryProposal(pid, address(0));
    }

    // =========================================================================
    //  6. retryProposal — new recipient also blocked → ProposalFailed again,
    //     stays Failed, spentToday decremented back
    // =========================================================================

    /// When the new recipient is also transfer-blocked, the retry should NOT revert
    /// but the proposal should end up Failed again.
    function test_RetryProposal_NewRecipientBlocked_ReturnsFalse_SetsFailedAgain() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        // Block the new recipient as well
        usdc.setTransferBlocked(bob, true);

        vm.prank(owner);
        vault.retryProposal(pid, bob); // must NOT revert

        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Failed),
            "proposal must stay Failed when new recipient is also blocked");
    }

    /// spentToday decremented again after the second failure.
    function test_RetryProposal_NewRecipientBlocked_DecrementsSpentToday() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        uint256 spentAfterFirstFail = vault.spentToday();

        usdc.setTransferBlocked(bob, true);
        vm.prank(owner);
        vault.retryProposal(pid, bob);

        assertEq(vault.spentToday(), spentAfterFirstFail,
            "spentToday should be restored after second failure");
    }

    /// ProposalFailed emitted with the new recipient address.
    function test_RetryProposal_NewRecipientBlocked_EmitsProposalFailed() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        usdc.setTransferBlocked(bob, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.ProposalFailed(pid, bob, 50e6);
        vault.retryProposal(pid, bob);
    }

    /// Same scenario but via a reverting transfer.
    function test_RetryProposal_NewRecipientReverts_SetsFailedAgain() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        usdc.setTransferReverts(bob, true);

        vm.prank(owner);
        vault.retryProposal(pid, bob); // must NOT propagate the revert

        (, , , , AgentVault.ProposalState state) = vault.proposals(pid);
        assertEq(uint8(state), uint8(AgentVault.ProposalState.Failed));
    }

    /// ProposalFailed emitted (catch branch) in a re-failing retry.
    function test_RetryProposal_NewRecipientReverts_EmitsProposalFailed() public {
        uint256 pid = _driveToFailed(carol, 50e6);
        usdc.setTransferReverts(bob, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.ProposalFailed(pid, bob, 50e6);
        vault.retryProposal(pid, bob);
    }

    // =========================================================================
    //  7. releaseEscrow try/catch — transfer returns false
    //     → state stays Active, escrowedBalance restored, EscrowReleaseFailed,
    //       no revert
    // =========================================================================

    /// When usdc.transfer returns false for the payee, the escrow state must remain Active.
    function test_ReleaseEscrow_TransferReturnsFalse_StaysActive() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");

        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vault.releaseEscrow(eid);  // must NOT revert

        (, , , , AgentVault.EscrowState state) = vault.escrows(eid);
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Active),
            "escrow must remain Active when transfer returns false");
    }

    /// escrowedBalance must be restored (re-incremented) when the transfer returns false.
    function test_ReleaseEscrow_TransferReturnsFalse_RestoresEscrowedBalance() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");
        uint256 escrowedAfterCreate = vault.escrowedBalance(); // 100e6

        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vault.releaseEscrow(eid);

        assertEq(vault.escrowedBalance(), escrowedAfterCreate,
            "escrowedBalance should be restored when transfer returns false");
    }

    /// EscrowReleaseFailed must be emitted (not EscrowReleased) when transfer returns false.
    function test_ReleaseEscrow_TransferReturnsFalse_EmitsEscrowReleaseFailed() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");

        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.EscrowReleaseFailed(eid, carol, 100e6);
        vault.releaseEscrow(eid);
    }

    /// Payee's USDC balance must not increase when the transfer returns false.
    function test_ReleaseEscrow_TransferReturnsFalse_PayeeBalanceUnchanged() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");
        uint256 carolBefore = usdc.balanceOf(carol);

        usdc.setTransferBlocked(carol, true);

        vm.prank(owner);
        vault.releaseEscrow(eid);

        assertEq(usdc.balanceOf(carol), carolBefore,
            "payee balance should not change when transfer returns false");
    }

    /// Owner can retry releaseEscrow after the first failed attempt (state is still Active).
    function test_ReleaseEscrow_TransferReturnsFalse_CanRetryRelease() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");

        // First attempt: blocked → stays Active
        usdc.setTransferBlocked(carol, true);
        vm.prank(owner);
        vault.releaseEscrow(eid);

        // Unblock, then retry: should succeed
        usdc.setTransferBlocked(carol, false);
        uint256 carolBefore = usdc.balanceOf(carol);
        vm.prank(owner);
        vault.releaseEscrow(eid);  // second attempt — must succeed

        (, , , , AgentVault.EscrowState state) = vault.escrows(eid);
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Released));
        assertEq(usdc.balanceOf(carol), carolBefore + 100e6);
    }

    // =========================================================================
    //  8. releaseEscrow try/catch — transfer reverts
    //     → state stays Active, escrowedBalance restored, EscrowReleaseFailed,
    //       no revert
    // =========================================================================

    /// When usdc.transfer reverts for the payee, the escrow state must remain Active.
    function test_ReleaseEscrow_TransferReverts_StaysActive() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");

        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vault.releaseEscrow(eid);  // must NOT propagate the revert

        (, , , , AgentVault.EscrowState state) = vault.escrows(eid);
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Active),
            "escrow must remain Active when transfer reverts");
    }

    /// escrowedBalance must be restored when the inner transfer reverts.
    function test_ReleaseEscrow_TransferReverts_RestoresEscrowedBalance() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");
        uint256 escrowedAfterCreate = vault.escrowedBalance();

        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vault.releaseEscrow(eid);

        assertEq(vault.escrowedBalance(), escrowedAfterCreate,
            "escrowedBalance should be restored when transfer reverts");
    }

    /// EscrowReleaseFailed must be emitted (catch branch).
    function test_ReleaseEscrow_TransferReverts_EmitsEscrowReleaseFailed() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");

        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit AgentVault.EscrowReleaseFailed(eid, carol, 100e6);
        vault.releaseEscrow(eid);
    }

    /// Payee's USDC balance must not increase when the inner transfer reverts.
    function test_ReleaseEscrow_TransferReverts_PayeeBalanceUnchanged() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");
        uint256 carolBefore = usdc.balanceOf(carol);

        usdc.setTransferReverts(carol, true);

        vm.prank(owner);
        vault.releaseEscrow(eid);

        assertEq(usdc.balanceOf(carol), carolBefore,
            "payee balance should not change when transfer reverts");
    }

    /// Owner can retry releaseEscrow after a reverting attempt (state is still Active).
    function test_ReleaseEscrow_TransferReverts_CanRetryRelease() public {
        vm.prank(alice);
        uint256 eid = vault.createEscrow(carol, 100e6, "cond");

        // First attempt: reverts → stays Active
        usdc.setTransferReverts(carol, true);
        vm.prank(owner);
        vault.releaseEscrow(eid);

        // Clear the revert flag and retry
        usdc.setTransferReverts(carol, false);
        uint256 carolBefore = usdc.balanceOf(carol);
        vm.prank(owner);
        vault.releaseEscrow(eid);  // second attempt — must succeed

        (, , , , AgentVault.EscrowState state) = vault.escrows(eid);
        assertEq(uint8(state), uint8(AgentVault.EscrowState.Released));
        assertEq(usdc.balanceOf(carol), carolBefore + 100e6);
    }

    // =========================================================================
    //  Boundary / regression: executeProposal on a Failed proposal reverts with
    //  ProposalAlreadyFailed (not InvalidProposalState).
    // =========================================================================

    function test_ExecuteProposal_RevertsWithProposalAlreadyFailed() public {
        uint256 pid = _driveToFailed(carol, 50e6);

        vm.prank(owner);
        vm.expectRevert(AgentVault.ProposalAlreadyFailed.selector);
        vault.executeProposal(pid);
    }
}
