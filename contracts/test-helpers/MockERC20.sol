// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal ERC-20 mock for unit tests.
///      Supports mint, burn, approve, transfer, transferFrom.
///      Returns false on transfer/transferFrom when flagged as "blocked" for
///      a recipient — used to test the splitPayment try/catch isolation path.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8  public decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Addresses whose incoming transfers will return false (simulates
    ///      a blocklisted recipient without reverting — tests the `ok == false` branch).
    mapping(address => bool) public transferBlocked;

    /// @dev Addresses whose incoming transfers will revert — tests the catch branch.
    mapping(address => bool) public transferReverts;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name     = _name;
        symbol   = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        totalSupply       += amount;
        balanceOf[to]     += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply     -= amount;
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (transferReverts[to]) revert("MockERC20: transfer reverts");
        if (transferBlocked[to]) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (transferReverts[to]) revert("MockERC20: transfer reverts");
        if (transferBlocked[to]) return false;
        // Insufficient allowance → return false (simulates a compliant ERC-20 that does NOT panic)
        if (allowance[from][msg.sender] < amount) return false;
        allowance[from][msg.sender] -= amount;
        balanceOf[from]             -= amount;
        balanceOf[to]               += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ── helpers to configure failure modes ────────────────────────────────────
    function setTransferBlocked(address who, bool blocked) external {
        transferBlocked[who] = blocked;
    }

    function setTransferReverts(address who, bool reverts) external {
        transferReverts[who] = reverts;
    }
}
