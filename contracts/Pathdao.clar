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

;; Route Optimization System
;; Advanced route optimization with traffic analysis and smart suggestions

(define-constant err-invalid-coordinates (err u109))
(define-constant err-optimization-failed (err u110))
(define-constant err-insufficient-data (err u111))
(define-constant err-invalid-time-window (err u112))

(define-data-var next-optimization-id uint u1)
(define-data-var optimization-enabled bool true)
(define-data-var traffic-analysis-fee uint u50000)

(define-map route-segments
  { segment-id: uint }
  {
    start-lat: int,
    start-lon: int,
    end-lat: int,
    end-lon: int,
    distance: uint,
    avg-speed: uint,
    traffic-density: uint,
    congestion-factor: uint,
    created-at: uint
  }
)

(define-map traffic-patterns
  { pattern-id: uint }
  {
    segment-id: uint,
    hour-of-day: uint,
    day-of-week: uint,
    avg-travel-time: uint,
    congestion-level: uint,
    sample-size: uint,
    last-updated: uint
  }
)

(define-map route-optimizations
  { optimization-id: uint }
  {
    route-id: uint,
    original-distance: uint,
    optimized-distance: uint,
    original-time: uint,
    optimized-time: uint,
    fuel-savings: uint,
    alternative-routes: (list 5 uint),
    confidence-score: uint,
    created-by: principal,
    created-at: uint
  }
)

(define-map delivery-performance
  { route-id: uint, courier: principal }
  {
    planned-time: uint,
    actual-time: uint,
    efficiency-score: uint,
    fuel-consumption: uint,
    delays-encountered: uint,
    route-deviations: uint,
    weather-impact: uint,
    traffic-impact: uint
  }
)

(define-map smart-suggestions
  { suggestion-id: uint }
  {
    route-id: uint,
    suggestion-type: uint,
    priority: uint,
    estimated-benefit: uint,
    description: (string-ascii 200),
    acceptance-rate: uint,
    success-rate: uint,
    created-at: uint
  }
)

(define-map courier-optimization-preferences
  { courier: principal }
  {
    prefer-shortest-distance: bool,
    prefer-fastest-time: bool,
    prefer-fuel-efficient: bool,
    avoid-tolls: bool,
    avoid-highways: bool,
    max-detour-percent: uint,
    preferred-speed: uint,
    vehicle-type: uint
  }
)

(define-public (create-route-segment
  (start-lat int)
  (start-lon int)
  (end-lat int)
  (end-lon int)
  (distance uint)
  (avg-speed uint))
  (let
    (
      (segment-id (var-get next-optimization-id))
      (current-block stacks-block-height)
    )
    (asserts! (var-get optimization-enabled) err-optimization-failed)
    (asserts! (and (>= start-lat -90000000) (<= start-lat 90000000)) err-invalid-coordinates)
    (asserts! (and (>= start-lon -180000000) (<= start-lon 180000000)) err-invalid-coordinates)
    (asserts! (and (>= end-lat -90000000) (<= end-lat 90000000)) err-invalid-coordinates)
    (asserts! (and (>= end-lon -180000000) (<= end-lon 180000000)) err-invalid-coordinates)
    (asserts! (> distance u0) err-invalid-coordinates)
    (asserts! (and (>= avg-speed u1) (<= avg-speed u200)) err-invalid-coordinates)
    
    (map-set route-segments
      { segment-id: segment-id }
      {
        start-lat: start-lat,
        start-lon: start-lon,
        end-lat: end-lat,
        end-lon: end-lon,
        distance: distance,
        avg-speed: avg-speed,
        traffic-density: u50,
        congestion-factor: u100,
        created-at: current-block
      }
    )
    (var-set next-optimization-id (+ segment-id u1))
    (ok segment-id)
  )
)

(define-public (record-traffic-pattern
  (segment-id uint)
  (hour-of-day uint)
  (day-of-week uint)
  (travel-time uint)
  (congestion-level uint))
  (let
    (
      (pattern-id (+ (* segment-id u1000) (+ (* hour-of-day u10) day-of-week)))
      (current-block stacks-block-height)
      (existing-pattern (map-get? traffic-patterns { pattern-id: pattern-id }))
    )
    (asserts! (var-get optimization-enabled) err-optimization-failed)
    (asserts! (<= hour-of-day u23) err-invalid-time-window)
    (asserts! (and (>= day-of-week u1) (<= day-of-week u7)) err-invalid-time-window)
    (asserts! (> travel-time u0) err-invalid-time-window)
    (asserts! (<= congestion-level u100) err-invalid-time-window)
    (asserts! (is-some (map-get? route-segments { segment-id: segment-id })) err-not-found)
    
    (match existing-pattern
      pattern (map-set traffic-patterns
        { pattern-id: pattern-id }
        {
          segment-id: segment-id,
          hour-of-day: hour-of-day,
          day-of-week: day-of-week,
          avg-travel-time: (/ (+ (* (get avg-travel-time pattern) (get sample-size pattern)) travel-time) (+ (get sample-size pattern) u1)),
          congestion-level: (/ (+ (* (get congestion-level pattern) (get sample-size pattern)) congestion-level) (+ (get sample-size pattern) u1)),
          sample-size: (+ (get sample-size pattern) u1),
          last-updated: current-block
        })
      (map-set traffic-patterns
        { pattern-id: pattern-id }
        {
          segment-id: segment-id,
          hour-of-day: hour-of-day,
          day-of-week: day-of-week,
          avg-travel-time: travel-time,
          congestion-level: congestion-level,
          sample-size: u1,
          last-updated: current-block
        })
    )
    (ok pattern-id)
  )
)

(define-public (optimize-route
  (route-id uint)
  (priority-factor uint)
  (fuel-price uint))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
      (optimization-id (var-get next-optimization-id))
      (current-block stacks-block-height)
      (base-distance (get distance route))
      (optimized-distance (calculate-optimized-distance base-distance priority-factor))
      (base-time (/ base-distance u50))
      (optimized-time (calculate-optimized-time base-time priority-factor))
      (fuel-savings (calculate-fuel-savings base-distance optimized-distance fuel-price))
      (confidence (calculate-confidence-score base-distance optimized-distance))
    )
    (asserts! (var-get optimization-enabled) err-optimization-failed)
    (asserts! (and (>= priority-factor u1) (<= priority-factor u5)) err-invalid-bid)
    (asserts! (> fuel-price u0) err-invalid-bid)
    (asserts! (or (is-eq (get status route) status-open) (is-eq (get status route) status-assigned)) err-route-closed)
    (try! (stx-transfer? (var-get traffic-analysis-fee) tx-sender (as-contract tx-sender)))
    
    (map-set route-optimizations
      { optimization-id: optimization-id }
      {
        route-id: route-id,
        original-distance: base-distance,
        optimized-distance: optimized-distance,
        original-time: base-time,
        optimized-time: optimized-time,
        fuel-savings: fuel-savings,
        alternative-routes: (list u1 u2 u3 u4 u5),
        confidence-score: confidence,
        created-by: tx-sender,
        created-at: current-block
      }
    )
    (var-set next-optimization-id (+ optimization-id u1))
    (ok optimization-id)
  )
)

(define-public (record-delivery-performance
  (route-id uint)
  (planned-time uint)
  (actual-time uint)
  (fuel-consumption uint)
  (delays uint)
  (deviations uint)
  (weather-impact uint)
  (traffic-impact uint))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) err-not-found))
      (courier (unwrap! (get assigned-courier route) err-unauthorized))
      (efficiency (calculate-efficiency-score planned-time actual-time))
    )
    (asserts! (is-eq tx-sender courier) err-unauthorized)
    (asserts! (is-eq (get status route) status-completed) err-invalid-status)
    (asserts! (> planned-time u0) err-invalid-time-window)
    (asserts! (> actual-time u0) err-invalid-time-window)
    (asserts! (<= weather-impact u100) err-invalid-time-window)
    (asserts! (<= traffic-impact u100) err-invalid-time-window)
    
    (map-set delivery-performance
      { route-id: route-id, courier: courier }
      {
        planned-time: planned-time,
        actual-time: actual-time,
        efficiency-score: efficiency,
        fuel-consumption: fuel-consumption,
        delays-encountered: delays,
        route-deviations: deviations,
        weather-impact: weather-impact,
        traffic-impact: traffic-impact
      }
    )
    (ok true)
  )
)

(define-public (create-smart-suggestion
  (route-id uint)
  (suggestion-type uint)
  (priority uint)
  (estimated-benefit uint)
  (description (string-ascii 200)))
  (let
    (
      (suggestion-id (var-get next-optimization-id))
      (current-block stacks-block-height)
    )
    (asserts! (var-get optimization-enabled) err-optimization-failed)
    (asserts! (is-some (map-get? routes { route-id: route-id })) err-not-found)
    (asserts! (and (>= suggestion-type u1) (<= suggestion-type u5)) err-invalid-bid)
    (asserts! (and (>= priority u1) (<= priority u5)) err-invalid-bid)
    (asserts! (> estimated-benefit u0) err-invalid-bid)
    
    (map-set smart-suggestions
      { suggestion-id: suggestion-id }
      {
        route-id: route-id,
        suggestion-type: suggestion-type,
        priority: priority,
        estimated-benefit: estimated-benefit,
        description: description,
        acceptance-rate: u0,
        success-rate: u0,
        created-at: current-block
      }
    )
    (var-set next-optimization-id (+ suggestion-id u1))
    (ok suggestion-id)
  )
)

(define-public (set-optimization-preferences
  (prefer-shortest bool)
  (prefer-fastest bool)
  (prefer-fuel-efficient bool)
  (avoid-tolls bool)
  (avoid-highways bool)
  (max-detour uint)
  (preferred-speed uint)
  (vehicle-type uint))
  (begin
    (asserts! (is-some (get-courier-by-address tx-sender)) err-unauthorized)
    (asserts! (<= max-detour u100) err-invalid-bid)
    (asserts! (and (>= preferred-speed u20) (<= preferred-speed u120)) err-invalid-bid)
    (asserts! (and (>= vehicle-type u1) (<= vehicle-type u5)) err-invalid-bid)
    
    (map-set courier-optimization-preferences
      { courier: tx-sender }
      {
        prefer-shortest-distance: prefer-shortest,
        prefer-fastest-time: prefer-fastest,
        prefer-fuel-efficient: prefer-fuel-efficient,
        avoid-tolls: avoid-tolls,
        avoid-highways: avoid-highways,
        max-detour-percent: max-detour,
        preferred-speed: preferred-speed,
        vehicle-type: vehicle-type
      }
    )
    (ok true)
  )
)

(define-public (toggle-optimization-system (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set optimization-enabled enabled)
    (ok enabled)
  )
)

(define-public (update-traffic-analysis-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-fee u0) err-invalid-bid)
    (var-set traffic-analysis-fee new-fee)
    (ok new-fee)
  )
)

(define-read-only (get-route-segment (segment-id uint))
  (map-get? route-segments { segment-id: segment-id })
)

(define-read-only (get-traffic-pattern (pattern-id uint))
  (map-get? traffic-patterns { pattern-id: pattern-id })
)

(define-read-only (get-route-optimization (optimization-id uint))
  (map-get? route-optimizations { optimization-id: optimization-id })
)

(define-read-only (get-delivery-performance (route-id uint) (courier principal))
  (map-get? delivery-performance { route-id: route-id, courier: courier })
)

(define-read-only (get-smart-suggestion (suggestion-id uint))
  (map-get? smart-suggestions { suggestion-id: suggestion-id })
)

(define-read-only (get-courier-preferences (courier principal))
  (map-get? courier-optimization-preferences { courier: courier })
)

(define-read-only (get-optimization-status)
  (var-get optimization-enabled)
)

(define-read-only (get-traffic-analysis-fee)
  (var-get traffic-analysis-fee)
)

(define-read-only (calculate-route-efficiency (route-id uint))
  (match (map-get? routes { route-id: route-id })
    route (let
      (
        (distance (get distance route))
        (base-time (/ distance u50))
        (optimization (get-route-optimization-by-route route-id))
      )
      (match optimization
        opt (/ (* (get optimized-distance opt) u100) distance)
        u100
      )
    )
    u0
  )
)

(define-read-only (predict-delivery-time (route-id uint) (current-hour uint) (current-day uint))
  (let
    (
      (route (unwrap! (map-get? routes { route-id: route-id }) u0))
      (base-time (/ (get distance route) u50))
      (traffic-factor (get-traffic-factor-for-time current-hour current-day))
    )
    (/ (* base-time traffic-factor) u100)
  )
)

(define-private (calculate-optimized-distance (base-distance uint) (priority uint))
  (let
    (
      (optimization-factor (+ u85 (* priority u3)))
    )
    (/ (* base-distance optimization-factor) u100)
  )
)

(define-private (calculate-optimized-time (base-time uint) (priority uint))
  (let
    (
      (time-factor (+ u80 (* priority u4)))
    )
    (/ (* base-time time-factor) u100)
  )
)

(define-private (calculate-fuel-savings (original-distance uint) (optimized-distance uint) (fuel-price uint))
  (let
    (
      (distance-saved (- original-distance optimized-distance))
      (fuel-per-km u8)
    )
    (/ (* distance-saved fuel-per-km fuel-price) u100)
  )
)

(define-private (calculate-confidence-score (original-distance uint) (optimized-distance uint))
  (let
    (
      (improvement-percent (/ (* (- original-distance optimized-distance) u100) original-distance))
    )
    (if (<= improvement-percent u5)
      u60
      (if (<= improvement-percent u15)
        u80
        u95
      )
    )
  )
)

(define-private (calculate-efficiency-score (planned-time uint) (actual-time uint))
  (if (<= actual-time planned-time)
    u100
    (/ (* planned-time u100) actual-time)
  )
)

(define-private (get-route-optimization-by-route (route-id uint))
  (map-get? route-optimizations { optimization-id: u1 })
)



(define-private (get-traffic-factor-for-time (hour uint) (day uint))
  (if (and (>= hour u7) (<= hour u9))
    u150
    (if (and (>= hour u17) (<= hour u19))
      u140
      (if (and (>= day u6) (<= day u7))
        u120
        u100
      )
    )
  )
)