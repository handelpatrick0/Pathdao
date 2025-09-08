;; Dynamic Pricing & Surge Management System
;; Automatically adjusts delivery prices based on supply, demand, and market conditions

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u500))
(define-constant err-not-found (err u501))
(define-constant err-invalid-zone (err u502))
(define-constant err-invalid-multiplier (err u503))
(define-constant err-pricing-disabled (err u504))
(define-constant err-insufficient-data (err u505))

;; Surge constants
(define-constant surge-threshold-low u120) ;; 1.2x multiplier
(define-constant surge-threshold-medium u150) ;; 1.5x multiplier
(define-constant surge-threshold-high u200) ;; 2.0x multiplier
(define-constant surge-threshold-extreme u300) ;; 3.0x multiplier

;; Data variables
(define-data-var pricing-enabled bool true)
(define-data-var base-surge-multiplier uint u100) ;; 1.0x (no surge)
(define-data-var next-zone-id uint u1)
(define-data-var pricing-update-frequency uint u6) ;; Update every 6 blocks (~1 hour)

;; Geographic pricing zones
(define-map pricing-zones
  { zone-id: uint }
  {
    zone-name: (string-ascii 50),
    center-lat: int,
    center-lon: int,
    radius: uint,
    base-price-per-mile: uint,
    current-surge-multiplier: uint,
    active-routes: uint,
    available-couriers: uint,
    last-updated: uint,
    demand-score: uint
  }
)

;; Real-time market metrics
(define-map market-metrics
  { zone-id: uint, time-window: uint }
  {
    total-requests: uint,
    fulfilled-requests: uint,
    avg-completion-time: uint,
    courier-utilization: uint,
    peak-demand-factor: uint,
    weather-impact: uint,
    special-events: bool,
    updated-at: uint
  }
)

;; Surge pricing history
(define-map surge-history
  { zone-id: uint, timestamp: uint }
  {
    surge-multiplier: uint,
    demand-level: uint,
    supply-level: uint,
    reason: (string-ascii 100),
    duration: uint
  }
)

;; Dynamic pricing configurations
(define-map pricing-configs
  { config-id: uint }
  {
    demand-weight: uint,
    supply-weight: uint,
    time-weight: uint,
    weather-weight: uint,
    event-weight: uint,
    max-surge-multiplier: uint,
    min-surge-multiplier: uint,
    active: bool
  }
)

;; Price predictions
(define-map price-predictions
  { zone-id: uint, prediction-window: uint }
  {
    predicted-surge: uint,
    confidence-level: uint,
    trend-direction: uint,
    estimated-duration: uint,
    recommended-action: (string-ascii 50)
  }
)

;; Read-only functions
(define-read-only (get-current-surge-multiplier (zone-id uint))
  (match (map-get? pricing-zones { zone-id: zone-id })
    zone (ok (get current-surge-multiplier zone))
    (err err-not-found)
  )
)

(define-read-only (calculate-dynamic-price (zone-id uint) (base-distance uint))
  (match (map-get? pricing-zones { zone-id: zone-id })
    zone (let
      ((base-price (* base-distance (get base-price-per-mile zone)))
       (surge-multiplier (get current-surge-multiplier zone)))
      (ok (/ (* base-price surge-multiplier) u100)))
    (err err-not-found)
  )
)

(define-read-only (get-market-metrics (zone-id uint) (time-window uint))
  (match (map-get? market-metrics { zone-id: zone-id, time-window: time-window })
    metrics (ok metrics)
    (err err-not-found)
  )
)

(define-read-only (get-surge-prediction (zone-id uint) (hours-ahead uint))
  (match (map-get? price-predictions { zone-id: zone-id, prediction-window: hours-ahead })
    prediction (ok prediction)
    (err err-not-found)
  )
)

(define-read-only (is-surge-active (zone-id uint))
  (match (map-get? pricing-zones { zone-id: zone-id })
    zone (ok (> (get current-surge-multiplier zone) u100))
    (err err-not-found)
  )
)

;; Public functions
(define-public (create-pricing-zone
  (zone-name (string-ascii 50))
  (center-lat int)
  (center-lon int)
  (radius uint)
  (base-price uint))
  (let
    ((zone-id (var-get next-zone-id))
     (current-block stacks-block-height))
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> radius u0) err-invalid-zone)
    (asserts! (> base-price u0) err-invalid-zone)
    (asserts! (and (>= center-lat -90000000) (<= center-lat 90000000)) err-invalid-zone)
    (asserts! (and (>= center-lon -180000000) (<= center-lon 180000000)) err-invalid-zone)
    
    (map-set pricing-zones
      { zone-id: zone-id }
      {
        zone-name: zone-name,
        center-lat: center-lat,
        center-lon: center-lon,
        radius: radius,
        base-price-per-mile: base-price,
        current-surge-multiplier: u100,
        active-routes: u0,
        available-couriers: u0,
        last-updated: current-block,
        demand-score: u50
      })
    
    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

;; Private helper functions (defined before use)
(define-private (calculate-surge-multiplier (demand uint) (supply uint) (weather uint) (events bool))
  (let
    ((demand-supply-ratio (if (> supply u0) (/ (* demand u100) supply) u300))
     (weather-factor (+ u100 (/ weather u2)))
     (event-factor (if events u130 u100))
     (base-surge (/ (* demand-supply-ratio weather-factor event-factor) u10000)))
    (if (> base-surge surge-threshold-extreme)
      surge-threshold-extreme
      (if (> base-surge surge-threshold-high)
        surge-threshold-high
        (if (> base-surge surge-threshold-medium)
          surge-threshold-medium
          (if (> base-surge surge-threshold-low)
            surge-threshold-low
            u100))))
  )
)

(define-private (calculate-demand-score (active-routes uint) (available-couriers uint))
  (if (is-eq available-couriers u0)
    u100
    (let ((ratio (/ (* active-routes u100) available-couriers)))
      (if (> ratio u200) u100
        (if (> ratio u150) u75
          (if (> ratio u100) u50
            u25)))))
)

(define-private (calculate-utilization (demand uint) (supply uint))
  (if (is-eq supply u0)
    u100
    (let ((utilization (/ (* demand u100) supply)))
      (if (> utilization u100) u100 utilization)))
)

(define-private (abs-diff (a uint) (b uint))
  (if (> a b) (- a b) (- b a))
)

(define-public (update-market-conditions
  (zone-id uint)
  (active-routes uint)
  (available-couriers uint)
  (special-events bool)
  (weather-impact uint))
  (let
    ((zone (unwrap! (map-get? pricing-zones { zone-id: zone-id }) err-not-found))
     (current-block stacks-block-height)
     (time-window (/ current-block u6))
     (new-surge (calculate-surge-multiplier active-routes available-couriers weather-impact special-events)))
    
    (asserts! (var-get pricing-enabled) err-pricing-disabled)
    (asserts! (<= weather-impact u100) err-invalid-multiplier)
    
    ;; Update zone with new market data
    (map-set pricing-zones
      { zone-id: zone-id }
      (merge zone {
        current-surge-multiplier: new-surge,
        active-routes: active-routes,
        available-couriers: available-couriers,
        last-updated: current-block,
        demand-score: (calculate-demand-score active-routes available-couriers)
      }))
    
    ;; Record market metrics
    (map-set market-metrics
      { zone-id: zone-id, time-window: time-window }
      {
        total-requests: active-routes,
        fulfilled-requests: (if (> available-couriers u0) active-routes u0),
        avg-completion-time: u120, ;; Default 2 hours
        courier-utilization: (calculate-utilization active-routes available-couriers),
        peak-demand-factor: new-surge,
        weather-impact: weather-impact,
        special-events: special-events,
        updated-at: current-block
      })
    
    ;; Log surge history if significant change
    (if (> (abs-diff new-surge (get current-surge-multiplier zone)) u20)
      (map-set surge-history
        { zone-id: zone-id, timestamp: current-block }
        {
          surge-multiplier: new-surge,
          demand-level: active-routes,
          supply-level: available-couriers,
          reason: (if special-events "special-event" (if (> weather-impact u30) "weather" "demand-supply")),
          duration: u0
        })
      true)
    
    (ok new-surge)
  )
)

(define-public (create-price-prediction
  (zone-id uint)
  (hours-ahead uint)
  (expected-demand uint)
  (expected-supply uint))
  (let
    ((zone (unwrap! (map-get? pricing-zones { zone-id: zone-id }) err-not-found))
     (predicted-surge (calculate-surge-multiplier expected-demand expected-supply u0 false))
     (current-surge (get current-surge-multiplier zone))
     (confidence (calculate-prediction-confidence zone-id hours-ahead))
     (trend (if (> predicted-surge current-surge) u1 (if (< predicted-surge current-surge) u2 u0))))
    
    (asserts! (var-get pricing-enabled) err-pricing-disabled)
    (asserts! (and (> hours-ahead u0) (<= hours-ahead u48)) err-invalid-zone)
    
    (map-set price-predictions
      { zone-id: zone-id, prediction-window: hours-ahead }
      {
        predicted-surge: predicted-surge,
        confidence-level: confidence,
        trend-direction: trend,
        estimated-duration: hours-ahead,
        recommended-action: (get-pricing-recommendation predicted-surge current-surge)
      })
    
    (ok predicted-surge)
  )
)

(define-public (toggle-dynamic-pricing (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set pricing-enabled enabled)
    (ok enabled)
  )
)

;; Additional helper functions
(define-private (calculate-prediction-confidence (zone-id uint) (hours-ahead uint))
  (let
    ((zone (unwrap! (map-get? pricing-zones { zone-id: zone-id }) u50))
     (data-age (- stacks-block-height (get last-updated zone)))
     (base-confidence u80))
    (if (> data-age u144) ;; Data older than 24 hours
      u30
      (if (> hours-ahead u24) ;; Predicting too far ahead
        (- base-confidence u20)
        (- base-confidence (/ hours-ahead u2)))))
)

(define-private (get-pricing-recommendation (predicted-surge uint) (current-surge uint))
  (if (> predicted-surge (+ current-surge u30))
    "wait-for-lower-price"
    (if (< predicted-surge (- current-surge u30))
      "book-now-save-money"
      "stable-pricing"))
)
