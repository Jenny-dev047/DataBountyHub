# DataBountyHub

A decentralized marketplace where AI researchers post bounties for specific datasets and community members contribute data for rewards.

## Features

- **Bounty Creation**: Researchers can create bounties for specific data types with STX rewards
- **Data Submission**: Contributors submit data with cryptographic hashes for verification
- **Reward Distribution**: Automatic payment upon bounty creator approval
- **Deadline Management**: Time-bounded bounties with automatic expiration
- **Duplicate Prevention**: Users can only submit once per bounty

## Contract Functions

### Public Functions
- `create-bounty(title, description, reward, duration, data-type)` - Create a new data bounty
- `submit-data(bounty-id, data-hash)` - Submit data for a bounty
- `approve-submission(submission-id)` - Approve submission and distribute reward

### Read-Only Functions
- `get-bounty(bounty-id)` - Retrieve bounty details
- `get-submission(submission-id)` - Get submission information
- `has-submitted(bounty-id, contributor)` - Check if user submitted to bounty
- `get-bounty-count()` - Get total number of bounties

## Usage

1. Researchers create bounties with `create-bounty`, funding them with STX
2. Contributors submit data using `submit-data` with data hashes
3. Bounty creators review submissions and approve with `approve-submission`
4. Rewards are automatically transferred to approved contributors

## Data Integrity

Data submissions are tracked using cryptographic hashes to ensure integrity and prevent tampering.

## Testing

Run tests using Clarinet:
```bash
clarinet test