// ABI for AgentVault — generated from contracts/AgentVault.sol
export const AGENT_VAULT_ABI = [
  // errors
  { type: 'error', name: 'ExceedsDailyCap', inputs: [] },
  { type: 'error', name: 'ExceedsPerTxCap', inputs: [] },
  { type: 'error', name: 'InsufficientVaultBalance', inputs: [] },
  { type: 'error', name: 'InvalidBps', inputs: [] },
  { type: 'error', name: 'InvalidEscrowState', inputs: [] },
  { type: 'error', name: 'InvalidProposalState', inputs: [] },
  { type: 'error', name: 'NotOwner', inputs: [] },
  { type: 'error', name: 'NotProposer', inputs: [] },
  { type: 'error', name: 'ProposalAlreadyFailed', inputs: [] },
  { type: 'error', name: 'ZeroAddress', inputs: [] },
  { type: 'error', name: 'ZeroAmount', inputs: [] },
  // events
  {
    type: 'event', name: 'VaultFunded',
    inputs: [{ name: 'sender', type: 'address', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'CapsUpdated',
    inputs: [{ name: 'perTxCap', type: 'uint256', indexed: false }, { name: 'dailyCap', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'AgentApproved',
    inputs: [{ name: 'agent', type: 'address', indexed: true }],
  },
  {
    type: 'event', name: 'AgentRevoked',
    inputs: [{ name: 'agent', type: 'address', indexed: true }],
  },
  {
    type: 'event', name: 'PaymentProposed',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'proposer', type: 'address', indexed: true },
      { name: 'recipient', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'reason', type: 'string', indexed: false },
    ],
  },
  {
    type: 'event', name: 'ProposalApproved',
    inputs: [{ name: 'proposalId', type: 'uint256', indexed: true }],
  },
  {
    type: 'event', name: 'ProposalRejected',
    inputs: [{ name: 'proposalId', type: 'uint256', indexed: true }],
  },
  {
    type: 'event', name: 'ProposalExecuted',
    inputs: [{ name: 'proposalId', type: 'uint256', indexed: true }, { name: 'recipient', type: 'address', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'ProposalFailed',
    inputs: [{ name: 'proposalId', type: 'uint256', indexed: true }, { name: 'recipient', type: 'address', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'EscrowCreated',
    inputs: [
      { name: 'escrowId', type: 'uint256', indexed: true },
      { name: 'proposer', type: 'address', indexed: true },
      { name: 'payee', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'condition', type: 'string', indexed: false },
    ],
  },
  {
    type: 'event', name: 'EscrowReleased',
    inputs: [{ name: 'escrowId', type: 'uint256', indexed: true }, { name: 'payee', type: 'address', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'EscrowReleaseFailed',
    inputs: [{ name: 'escrowId', type: 'uint256', indexed: true }, { name: 'payee', type: 'address', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'EscrowRefunded',
    inputs: [{ name: 'escrowId', type: 'uint256', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'SplitPaymentExecuted',
    inputs: [{ name: 'totalAmount', type: 'uint256', indexed: false }, { name: 'recipientCount', type: 'uint256', indexed: false }, { name: 'skippedCount', type: 'uint256', indexed: false }],
  },
  {
    type: 'event', name: 'SplitPaymentSkipped',
    inputs: [{ name: 'recipient', type: 'address', indexed: true }, { name: 'amount', type: 'uint256', indexed: false }],
  },
  // constructor
  {
    type: 'constructor',
    inputs: [
      { name: 'usdcToken', type: 'address' },
      { name: '_perTxCap', type: 'uint256' },
      { name: '_dailyCap', type: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  // views
  { type: 'function', name: 'owner', inputs: [], outputs: [{ type: 'address' }], stateMutability: 'view' },
  { type: 'function', name: 'usdc', inputs: [], outputs: [{ type: 'address' }], stateMutability: 'view' },
  { type: 'function', name: 'perTxCap', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'dailyCap', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'spentToday', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'dayStart', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'escrowedBalance', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'isAgent', inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'bool' }], stateMutability: 'view' },
  { type: 'function', name: 'proposalsCount', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  { type: 'function', name: 'escrowsCount', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' },
  {
    type: 'function', name: 'proposals',
    inputs: [{ name: '', type: 'uint256' }],
    outputs: [
      { name: 'proposer', type: 'address' },
      { name: 'recipient', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'reason', type: 'string' },
      { name: 'state', type: 'uint8' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'escrows',
    inputs: [{ name: '', type: 'uint256' }],
    outputs: [
      { name: 'proposer', type: 'address' },
      { name: 'payee', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'condition', type: 'string' },
      { name: 'state', type: 'uint8' },
    ],
    stateMutability: 'view',
  },
  // writes
  {
    type: 'function', name: 'setCaps',
    inputs: [{ name: '_perTxCap', type: 'uint256' }, { name: '_dailyCap', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'approveAgent',
    inputs: [{ name: 'agent', type: 'address' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'revokeAgent',
    inputs: [{ name: 'agent', type: 'address' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'proposePayment',
    inputs: [{ name: 'recipient', type: 'address' }, { name: 'amount', type: 'uint256' }, { name: 'reason', type: 'string' }],
    outputs: [{ name: 'proposalId', type: 'uint256' }], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'approveProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'rejectProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'executeProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'retryProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }, { name: 'newRecipient', type: 'address' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'createEscrow',
    inputs: [{ name: 'payee', type: 'address' }, { name: 'amount', type: 'uint256' }, { name: 'condition', type: 'string' }],
    outputs: [{ name: 'escrowId', type: 'uint256' }], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'releaseEscrow',
    inputs: [{ name: 'escrowId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'refundEscrow',
    inputs: [{ name: 'escrowId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'splitPayment',
    inputs: [
      { name: 'recipients', type: 'address[]' },
      { name: 'bps', type: 'uint256[]' },
      { name: 'totalAmount', type: 'uint256' },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'fund',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
] as const
