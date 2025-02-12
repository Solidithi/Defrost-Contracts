# Contributing Guidelines

## Development Workflow

Typical workflow:

1. Make changes to `dev` branch
2. Ensure tests pass with `forge test`
3. Commit your chnages following our commit convention
4. Push your changes and create a pull request

If your changes are too large:

1. Create your branch from `dev`. Example branch: `fix/launchpool-withdraw/SCRUM-3-negative-withdraw-amount` (type/scope/issue-code)
2. Make your changes
3. Ensure tests pass with `forge test`
4. Commit your changes following our commit convention
5. Push your changes and create a Pull Request

## Code Style

# Code Style Guidelines

We adhere to the official code style framework: [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)

- 📝 Consistent code formatting
- 🔍 Maximum readability
- 🚀 Optimal performance
- 🛡️ Enhanced security
- 🤝 Better collaboration

Our style guide is strictly enforced through automated tools and code reviews.

### Formatting Rules

- Line length: max 120 characters
- Indentation: Tabs (width: 4)
- Quotes: Double quotes for strings
- Configured using `Prettier`

### Naming Conventions (referencing the [Solidity Style Guide Naming Convention](https://docs.soliditylang.org/en/latest/style-guide.html#naming-conventions)

- **Contracts**: PascalCase (e.g., `MyContract`)
- **Functions**: camelCase (e.g., `myFunction`)
- **Function Parameters**: camelCase (e.g, `withdrawAmount`)
- **Variables**: camelCase (e.g, `userBalance`)
- **Constants**: SNAKE_CASE (e.g, `MAX_AMOUNT`)
- **Immutable Variables**: treated as constants
- **Events**: PascalCase (e.g, `PoolCreated`)
- **Modifiers**: camelCase (e.g, `modifier isValidPoolId() {}`)
- **Private/Internal Variables**: must start with underscore (e.g., `uint256 private _privateVar`)
- **Private/Internal Functions**: must start with underscore (e.g., `function _validateInfo() internal {}`)

### Code Organization Rules

#### 1. Import statements at the top

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyToken is ERC20 {
	// Contract implementation here
}
```

#### 2. Follow the strict contract elements ordering rules defined by the [Solidity Style Guide Ordering Rules](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout)

Contract elements should be arranged in the following order:

1. Type declarations (using, enum, struct)
2. State variables
3. Events
4. Errors
5. Modifiers
6. Constructor
7. Receive function (if exists)
8. Fallback function (if exists)
9. External functions
10. Public functions
11. Internal functions
12. Private functions

Example:

```solidity
contract OrderedContract {
	// 1. Type declarations
	enum Status {
		Active,
		Inactive
	}
	struct User {
		address addr;
		uint256 balance;
	}

	// 2. State variables
	Status public status;

	// 3. Events
	event StatusChanged(Status newStatus);

	// 4. Errors
	error Unauthorized();

	// 5. Modifiers
	modifier onlyActive() {
		require(status == Status.Active);
		_;
	}

	// 6. Constructor
	constructor() {
		status = Status.Active;
	}

	// 7-8. Receive/Fallback (if needed)
	receive() external payable {}

	// 9-12. Functions ordered by visibility (external -> public -> internal -> private)
	function externalFunction() external {}
	function publicFunction() public {}
	function _internalFunction() internal {}
	function _privateFunction() private {}
}
```

#### 3. For each function visibility, functions should be ordered by type (normal -> view -> pure)

```solidity
contract MyContract {
	// External functions
	function externalFunc() external {}
	function externalViewFunc1() external view returns (uint256) {}
	function externalViewFunc2() external view returns (uint256) {}
	function externalPureFunc1() external pure returns (uint256) {}
	function externalPureFunc2() external pure returns (uint256) {}

	// Public functions
	function publicFunc() public {}
	function publicViewFunc1() public view returns (uint256) {}
	function publicViewFunc2() public view returns (uint256) {}
	function publicPureFunc1() public pure returns (uint256) {}
	function publicPureFunc2() public pure returns (uint256) {}

	// Internal functions
	function internalFunc() internal {}
	function internalViewFunc1() internal view returns (uint256) {}
	function internalViewFunc2() internal view returns (uint256) {}
	function internalPureFunc1() internal pure returns (uint256) {}
	function internalPureFunc2() internal pure returns (uint256) {}

	// Private functions
	function privateFunc() private {}
	function privateViewFunc1() private view returns (uint256) {}
	function privateViewFunc2() private view returns (uint256) {}
	function privatePureFunc1() private pure returns (uint256) {}
	function privatePureFunc2() private pure returns (uint256) {}
}
```

#### 4. State variables must have explicit visibility

```solidity
contract MyContract {
	address internal owner; // valid
	address owner; // invalid

	uint256 private userCount; // valid
	uint256 userCount; // invalid

	bool public isLocked; // valid
	bool isLocked; // invalid
}
```

#### 5. Avoid empty blocks

```solidity
contract MyContract {
	function processAction() public {
		if (msg.sender != owner) {
			revert("Unauthorized access");
		} else {
			// Action processing logic instead of leaving empty block
			// e.g., update state, emit event, etc.
		}
	}
}
```

### Gas Optimization Rules

#### 1. Use custom errors instead of revert strings (MUST)

Use `custom errors` and `fixed string` to revert errors <br>
Instead of using `require` statement with a `dynamic string`

Example:

```solidity
// Do this:
contract EfficientContract {
	error Unauthorized(address user);

	function authenticate(address user) public view {
		if (msg.sender != owner) {
			revert Unauthorized(user);
		}
	}
}

// Don't do this:
contract ExpensiveContract {
	string private _errorMessage = "Not authorized for ";

	function authenticate(address user) public view {
		require(msg.sender == owner, string(abi.encodePacked(_errorMessage, user)));
	}
}
```

This approach saves gas by:

- \*Important: using custom errors instead of revert strings
- Avoiding string concatenation operations
- Eliminating storage of error messages

This approach is more gas-efficient than using string-based revert messages.

#### 2. Cache array and array length for less gas usage (RECOMMENDED)

Without caching:

```solidity
contract Demo {
	function sum(uint256[] memory data) public pure returns (uint256) {
		// gas: 26645
		uint256 total = 0;
		for (uint256 i = 0; i < data.length; i++) {
			total += data[i];
		}
		return total;
	}
}
```

With caching:

```solidity
contract Demo {
	uint256[] internal _data;

	// ...

	function sum(uint256[] memory data) public pure returns (uint256) {
		// gas: 25560
		uint256 total = 0;
		uint256[] memory cachedData = _data; // caching here
		uint256 len = data.length; // caching here
		for (uint256 i = 0; i < len; i++) {
			total += data[i];
		}
		return total;
	}
}
```

#### 3. Use indexed parameters in events judiciously (RECOMMENDED)

Index only parameters that are needed for filtering:

```solidity
event Transfer(address indexed from, address indexed to, uint256 amount);
```

Avoid over-indexing to reduce gas costs.

#### 5. Optimize string usage for gas efficiency (RECOMMENDED)

## Commit Convention

Format: `<type>(<scope>): <subject>` or `<type>: <subject>`

### Types

- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation changes
- `style`: Code style/formatting changes
- `refactor`: Code changes that neither fix bugs nor add features
- `test`: Adding/updating tests
- `chore`: Tooling, dependencies, etc.
- `perf`: Performance improvements
- `ci`: CI/CD changes
- `build`: Build system changes
- `revert`: Reverting commits

### Rules

- Type must be lowercase
- Subject must be lowercase
- No period at end of subject
- Subject cannot be empty

### Examples

Valid:

```
feat(auth): add signature verification
fix: resolve reentrancy issue
refactor(storage): optimize gas usage
```

Invalid:

```
Feat: Add feature    # Wrong casing
fix: fixed bug.      # Has period
chore:              # Empty subject
```

## Pre-commit Hooks

We use Husky to run commit checks:

1. Check commit message format (Commitlint)
2. Linting (Solhint)
3. Code formatting (Prettier)
4. Tests (if .sol files are changed)

\*Important: your commit will be automatically rejected unless all checks pass
