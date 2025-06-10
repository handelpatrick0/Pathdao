;; title: Pathdao - Route Bidding Logistics Protocol
;; version: 1.0.0
;; summary: Decentralized logistics platform where couriers bid on delivery routes
;; description: A protocol enabling efficient route allocation through competitive bidding

;; traits
(define-trait courier-trait
  (
    (get-reputation () (response uint uint))
  )
)

;; token definitions
(define-fungible-token path-token)

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-bid (err u103))
(define-constant err-route-closed (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-already-exists (err u106))
(define-constant err-route-active (err u107))
(define-constant err-invalid-status (err u108))

;; Route status constants
(define-constant status-open u1)
(define-constant status-assigned u2)
(define-constant status-in-progress u3)
(define-constant status-completed u4)
(define-constant status-cancelled u5)

;; data vars
(define-data-var next-route-id uint u1)
(define-data-var next-courier-id uint u1)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var min-bid-amount uint u1000000) ;; 1 STX in microSTX

;; data maps
(define-map routes
  { route-id: uint }
  {
    creator: principal,
    origin: (string-ascii 100),
    destination: (string-ascii 100),
    distance: uint,
    max-weight: uint,
    deadline: uint,
    base-reward: uint,
    status: uint,
    assigned-courier: (optional principal),
    winning-bid: uint,
    created-at: uint
  }
)

(define-map couriers
  { courier-id: uint, address: principal }
  {
    name: (string-ascii 50),
    reputation-score: uint,
    total-deliveries: uint,
    successful-deliveries: uint,
    total-earnings: uint,
    is-active: bool,
    registered-at: uint
  }
)

(define-map route-bids
  { route-id: uint, courier: principal }
  {
    bid-amount: uint,
    estimated-time: uint,
    message: (string-ascii 200),
    bid-at: uint
  }
)

(define-map courier-routes
  { courier: principal, route-id: uint }
  { assigned-at: uint, completed-at: (optional uint) }
)

(define-map route-reviews
  { route-id: uint }
  {
    rating: uint,
    review: (string-ascii 500),
    reviewed-by: principal,
    reviewed-at: uint
  }
)

;; public functions

;; Initialize contract with initial token supply
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (ft-mint? path-token u1000000000000 contract-owner))
    (ok true)
  )
)

;; Register as a courier
(define-public (register-courier (name (string-ascii 50)))
  (let
    (
      (courier-id (var-get next-courier-id))
      (current-block stacks-block-height)
    )
    (asserts! (is-none (get-courier-by-address tx-sender)) err-already-exists)
    (map-set couriers
      { courier-id: courier-id, address: tx-sender }
      {
        name: name,
        reputation-score: u100,
        total-deliveries: u0,
        successful-deliveries: u0,
        total-earnings: u0,
        is-active: true,
        registered-at: current-block
      }
    )
    (var-set next-courier-id (+ courier-id u1))
    (ok courier-id)
  )
)

;; Create a new delivery route
(define-public (create-route 
  (origin (string-ascii 100))
  (destination (string-ascii 100))
  (distance uint)
  (max-weight uint)
  (deadline uint)
  (base-reward uint))
  (let
    (
      (route-id (var-get next-route-id))
      (current-block stacks-block-height)
    )
    (asserts! (> base-reward u0) err-invalid-bid)
    (asserts! (> deadline current-block) err-invalid-bid)
    (try! (stx-transfer? base-reward tx-sender (as-contract tx-sender)))
    (map-set routes
      { route-id: route-id }
      {
        creator: tx-sender,
        origin: origin,
        destination: destination,
        distance: distance,
        max-weight: max-weight,
        deadline: deadline,
        base-reward: base-reward,
        status: status-open,
        assigned-courier: none,
        winning-bid: u0,
        created-at: current-block
      }
    )
    (var-set next-route-id (+ route-id u1))
    (ok route-id)
  )
)

;; Place a bid on a route
(define-public (place-bid 
  (route-id uint)
  (bid-amount uint)
  (estimated-time uint)
  (message (string-ascii 200)))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
      (current-block stacks-block-height)
    )
    (asserts! (is-some (get-courier-by-address tx-sender)) err-unauthorized)
    (asserts! (is-eq (get status route) status-open) err-route-closed)
    (asserts! (>= bid-amount (var-get min-bid-amount)) err-invalid-bid)
    (asserts! (< current-block (get deadline route)) err-route-closed)
    (map-set route-bids
      { route-id: route-id, courier: tx-sender }
      {
        bid-amount: bid-amount,
        estimated-time: estimated-time,
        message: message,
        bid-at: current-block
      }
    )
    (ok true)
  )
)

;; Accept a bid and assign route
(define-public (accept-bid (route-id uint) (courier principal))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
      (bid (unwrap! (map-get? route-bids { route-id: route-id, courier: courier }) err-not-found))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get creator route)) err-unauthorized)
    (asserts! (is-eq (get status route) status-open) err-route-closed)
    (map-set routes
      { route-id: route-id }
      (merge route {
        status: status-assigned,
        assigned-courier: (some courier),
        winning-bid: (get bid-amount bid)
      })
    )
    (map-set courier-routes
      { courier: courier, route-id: route-id }
      { assigned-at: current-block, completed-at: none }
    )
    (ok true)
  )
)

;; Start delivery
(define-public (start-delivery (route-id uint))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
    )
    (asserts! (is-eq (some tx-sender) (get assigned-courier route)) err-unauthorized)
    (asserts! (is-eq (get status route) status-assigned) err-invalid-status)
    (map-set routes
      { route-id: route-id }
      (merge route { status: status-in-progress })
    )
    (ok true)
  )
)

;; Complete delivery
(define-public (complete-delivery (route-id uint))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
      (courier-address (unwrap! (get assigned-courier route) err-unauthorized))
      (current-block stacks-block-height)
      (platform-fee (/ (* (get base-reward route) (var-get platform-fee-rate)) u10000))
      (courier-payment (- (get base-reward route) platform-fee))
    )
    (asserts! (is-eq tx-sender courier-address) err-unauthorized)
    (asserts! (is-eq (get status route) status-in-progress) err-invalid-status)
    
    ;; Update route status
    (map-set routes
      { route-id: route-id }
      (merge route { status: status-completed })
    )
    
    ;; Update courier route completion
    (map-set courier-routes
      { courier: courier-address, route-id: route-id }
      { assigned-at: (default-to u0 (get assigned-at (map-get? courier-routes { courier: courier-address, route-id: route-id }))), completed-at: (some current-block) }
    )
    
    ;; Pay courier
    (try! (as-contract (stx-transfer? courier-payment tx-sender courier-address)))
    
    ;; Update courier stats
    (update-courier-stats courier-address true)
    
    (ok true)
  )
)

;; Submit review for completed delivery
(define-public (submit-review 
  (route-id uint)
  (rating uint)
  (review (string-ascii 500)))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get creator route)) err-unauthorized)
    (asserts! (is-eq (get status route) status-completed) err-invalid-status)
    (asserts! (<= rating u5) err-invalid-bid)
    (map-set route-reviews
      { route-id: route-id }
      {
        rating: rating,
        review: review,
        reviewed-by: tx-sender,
        reviewed-at: current-block
      }
    )
    (ok true)
  )
)

;; read only functions

;; Get route details
(define-read-only (get-route (route-id uint))
  (map-get? routes { route-id: route-id })
)

;; Get courier info by address
(define-read-only (get-courier-by-address (address principal))
  (let
    (
      (courier-key (get-courier-key address))
    )
    (match courier-key
      key (map-get? couriers key)
      none
    )
  )
)

;; Get bid for route and courier
(define-read-only (get-bid (route-id uint) (courier principal))
  (map-get? route-bids { route-id: route-id, courier: courier })
)

;; Get route review
(define-read-only (get-route-review (route-id uint))
  (map-get? route-reviews { route-id: route-id })
)

;; Get platform fee rate
(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

;; Get minimum bid amount
(define-read-only (get-min-bid-amount)
  (var-get min-bid-amount)
)

;; Get next route ID
(define-read-only (get-next-route-id)
  (var-get next-route-id)
)

;; Check if route is expired
(define-read-only (is-route-expired (route-id uint))
  (match (map-get? routes { route-id: route-id })
    route (> stacks-block-height (get deadline route))
    false
  )
)

;; private functions

;; Helper function to get courier data
(define-private (get-courier-data (courier-entry { courier-id: uint, address: principal }))
  (map-get? couriers courier-entry)
)

;; Update courier statistics
(define-private (update-courier-stats (courier-address principal) (successful bool))
  (let
    (
      (courier-key (unwrap! (get-courier-key courier-address) false))
      (courier-data (unwrap! (map-get? couriers courier-key) false))
    )
    (map-set couriers
      courier-key
      (merge courier-data {
        total-deliveries: (+ (get total-deliveries courier-data) u1),
        successful-deliveries: (if successful 
          (+ (get successful-deliveries courier-data) u1)
          (get successful-deliveries courier-data)
        ),
        reputation-score: (calculate-reputation-score 
          (+ (get total-deliveries courier-data) u1)
          (if successful 
            (+ (get successful-deliveries courier-data) u1)
            (get successful-deliveries courier-data)
          )
        )
      })
    )
    true
  )
)

;; Get courier key by address
(define-private (get-courier-key (address principal))
  (let
    (
      (potential-keys (list 
        { courier-id: u1, address: address }
        { courier-id: u2, address: address }
        { courier-id: u3, address: address }
        { courier-id: u4, address: address }
        { courier-id: u5, address: address }
      ))
    )
    (fold find-courier-key potential-keys none)
  )
)

;; Helper to find courier key
(define-private (find-courier-key 
  (key { courier-id: uint, address: principal })
  (acc (optional { courier-id: uint, address: principal })))
  (if (is-some acc)
    acc
    (if (is-some (map-get? couriers key))
      (some key)
      none
    )
  )
)

;; Calculate reputation score based on success rate
(define-private (calculate-reputation-score (total uint) (successful uint))
  (if (is-eq total u0)
    u100
    (+ u50 (/ (* successful u50) total))
  )
)