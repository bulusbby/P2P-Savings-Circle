# 💰 P2P Savings Circle (Ajo)

A decentralized thrift contribution system that automates rotational savings using Clarity smart contracts on the Stacks blockchain.

## 🌟 Overview

The P2P Savings Circle contract enables groups of people to create and participate in traditional rotating savings and credit associations (ROSCAs), commonly known as "Ajo" in Nigeria, "Tanda" in Mexico, or "Susus" in Ghana.

### ✨ Key Features

- 🏗️ **Create Circles**: Start a savings circle with customizable parameters
- 👥 **Join Circles**: Become a member of existing circles
- 💵 **Contribute**: Make regular contributions to the pool
- 🎯 **Automatic Distribution**: Smart contract handles payout distribution
- 🔄 **Rotating System**: Each member receives the full pot in turn
- 📊 **Transparent Tracking**: All contributions and payouts are recorded on-chain

## 🚀 How It Works

1. **Circle Creation**: A creator sets up a circle with contribution amount, max members, and duration
2. **Member Joining**: Users join the circle until it reaches capacity
3. **Contribution Phase**: Members contribute the agreed amount each cycle
4. **Payout Distribution**: When all members contribute, the full pot goes to the next recipient
5. **Rotation**: The process repeats until everyone has received a payout

## 🛠️ Contract Functions

### Public Functions

#### `create-circle`
```clarity
(create-circle (name (string-ascii 50)) (contribution-amount uint) (max-members uint) (duration-blocks uint))
```
Creates a new savings circle.

**Parameters:**
- `name`: Circle name (max 50 characters)
- `contribution-amount`: Amount each member contributes per cycle (in microSTX)
- `max-members`: Maximum number of members (3-20)
- `duration-blocks`: Duration of each cycle in blocks

#### `join-circle`
```clarity
(join-circle (circle-id uint))
```
Join an existing active circle.

#### `contribute`
```clarity
(contribute (circle-id uint))
```
Make a contribution to your circle for the current cycle.

#### `distribute-payout`
```clarity
(distribute-payout (circle-id uint))
```
Distribute the current pot to the next recipient (callable by anyone when cycle is complete).

#### `close-circle`
```clarity
(close-circle (circle-id uint))
```
Close a circle (only by creator).

### Read-Only Functions

#### `get-circle`
```clarity
(get-circle (circle-id uint))
```
Get circle information.

#### `get-circle-stats`
```clarity
(get-circle-stats (circle-id uint))
```
Get circle statistics including member count and total contributions.

#### `get-member-info`
```clarity
(get-member-info (circle-id uint) (member principal))
```
Get member information for a specific circle.

#### `check-cycle-complete`
```clarity
(check-cycle-complete (circle-id uint))
```
Check if all members have contributed for the current cycle.

#### `get-next-recipient`
```clarity
(get-next-recipient (circle-id uint))
```
Get the next member to receive payout.

## 📋 Usage Example

### 1. Create a Circle
```clarity
(contract-call? .P2P-Savings-Circle create-circle "Friends Circle" u1000000 u5 u144)
```
Creates a circle where 5 friends contribute 1 STX each cycle, with cycles lasting ~1 day (144 blocks).

### 2. Join the Circle
```clarity
(contract-call? .P2P-Savings-Circle join-circle u1)
```

### 3. Make Contributions
```clarity
(contract-call? .P2P-Savings-Circle contribute u1)
```

### 4. Distribute Payout
```clarity
(contract-call? .P2P-Savings-Circle distribute-payout u1)
```

## 🔧 Development Setup

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet)
- Node.js (for testing)

### Installation
```bash
git clone https://github.com/bulusbby/P2P-Savings-Circle
cd P2P-Savings-Circle
clarinet check
```

### Testing
```bash
clarinet test
```

## 🛡️ Security Features

- ✅ **Member Validation**: Only members can contribute
- ✅ **Double-Spend Protection**: Members can't contribute twice per cycle
- ✅ **Access Control**: Only creators can close their circles
- ✅ **Automatic Payouts**: Smart contract handles distribution fairly
- ✅ **Transparent Operations**: All activities are recorded on-chain

## 📊 Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | err-owner-only | Only circle creator can perform this action |
| u101 | err-not-found | Circle or data not found |
| u102 | err-already-exists | Member already exists in circle |
| u103 | err-invalid-amount | Invalid contribution amount or parameters |
| u104 | err-circle-full | Circle has reached maximum members |
| u105 | err-not-member | User is not a member of this circle |
| u106 | err-already-paid | Member already contributed this cycle |
| u107 | err-circle-not-active | Circle is not active |
| u108 | err-invalid-recipient | Invalid payout recipient |
| u109 | err-cycle-not-complete | Not all members have contributed |
| u110 | err-insufficient-funds | Insufficient funds for operation |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

## 🌍 Cultural Context

Rotating Savings and Credit Associations (ROSCAs) are traditional financial systems used worldwide:
- **Nigeria**: Ajo, Esusu
- **Mexico**: Tanda
- **Ghana**: Susu
- **China**: Hui
- **India**: Chit Fund

This smart contract brings these time-tested financial practices to the blockchain, enabling global participation with transparency and automation.
