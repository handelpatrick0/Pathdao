# 🚚 Pathdao - Route Bidding Logistics Protocol

> *Where efficiency meets opportunity in decentralized delivery* ✨

## What's This All About? 🤔

Pathdao is a **decentralized logistics platform** built on Stacks that revolutionizes how deliveries work. Think Uber for packages, but **completely decentralized**! 📦

Shippers post delivery routes, couriers bid competitively, and the best bid wins. No middleman taking huge cuts - just pure market efficiency powered by blockchain tech.

## 🌟 Key Features

- **📍 Route Creation**: Post delivery jobs with origin, destination, and rewards
- **💰 Competitive Bidding**: Couriers compete with bids and estimated delivery times
- **⭐ Reputation System**: Build trust through successful deliveries and reviews
- **🔒 Escrow Protection**: Funds held securely until delivery completion
- **📊 Performance Tracking**: Track delivery stats and earnings
- **💎 Native Token**: PATH tokens for platform governance and rewards

## 🚀 Quick Start

### For Shippers 📤

1. **Create a Route**
```clarity
(contract-call? .pathdao create-route 
  "123 Main St, NYC" 
  "456 Oak Ave, LA" 
  u2500  ;; distance in miles
  u50    ;; max weight in lbs
  u1000  ;; deadline (block height)
  u5000000) ;; reward in microSTX
```

2. **Accept the Best Bid**
```clarity
(contract-call? .pathdao accept-bid u1 'SP1ABC...COURIER)
```

3. **Leave a Review**
```clarity
(contract-call? .pathdao submit-review u1 u5 "Amazing service!")
```

### For Couriers 🏃‍♂️

1. **Register as Courier**
```clarity
(contract-call? .pathdao register-courier "FastDelivery Co")
```

2. **Place Competitive Bids**
```clarity
(contract-call? .pathdao place-bid 
  u1           ;; route-id
  u4500000     ;; bid amount
  u24          ;; estimated hours
  "Express delivery with tracking!")
```

3. **Complete Deliveries**
```clarity
(contract-call? .pathdao start-delivery u1)
(contract-call? .pathdao complete-delivery u1)
```

## 📋 Route Status Flow

```
🟢 OPEN → 🟡 ASSIGNED → 🔵 IN-PROGRESS → ✅ COMPLETED
                ↓
            🔴 CANCELLED
```

## 💡 Smart Contract Functions

### Public Functions
- `initialize()` - Set up the contract (owner only)
- `register-courier(name)` - Join as a delivery courier
- `create-route(...)` - Post a new delivery job
- `place-bid(...)` - Bid on available routes
- `accept-bid(route-id, courier)` - Accept a courier's bid
- `start-delivery(route-id)` - Begin the delivery process
- `complete-delivery(route-id)` - Finish delivery and get paid
- `submit-review(...)` - Rate completed deliveries

### Read-Only Functions
- `get-route(route-id)` - View route details
- `get-courier-by-address(address)` - Check courier info
- `get-bid(route-id, courier)` - View specific bids
- `get-route-review(route-id)` - Read delivery reviews
- `is-route-expired(route-id)` - Check if deadline passed

## 🏗️ Development Setup

```bash
# Clone and setup
git clone <your-repo>
cd pathdao
clarinet check
```

```bash
# Run tests
clarinet test
```

```bash
# Deploy locally
clarinet console
```

## 🎯 Use Cases

- **📦 E-commerce Deliveries**: Last-mile delivery for online stores
- **🍕 Food Delivery**: Restaurant to customer logistics
- **📄 Document Courier**: Legal and business document delivery
- **🎁 Gift Delivery**: Personal package delivery service
- **🏢 B2B Logistics**: Inter-business delivery solutions

## 💰 Economics

- **Platform Fee**: 2.5% of successful deliveries
- **Minimum Bid**: 1 STX to prevent spam
- **Reputation Scoring**: Success rate impacts future opportunities
- **Automatic Payments**: Smart contract handles all transactions

## 🔐 Security Features

- ✅ Escrow system protects both parties
- ✅ Reputation system prevents bad actors
- ✅ Time-based route expiration
- ✅ Multi-signature support ready
- ✅ Comprehensive error handling

## 🤝 Contributing

We're building the future of logistics! 

1. Fork the repo
2. Create your feature branch
3. Write tests for new functionality
4. Submit a PR with clear description

## 📜 License

MIT License - Build amazing things! 🚀

## 🌐 Links

- **Documentation**: Coming soon
- **Discord**: Join our community
