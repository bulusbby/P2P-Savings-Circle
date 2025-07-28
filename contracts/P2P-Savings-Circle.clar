(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-circle-full (err u104))
(define-constant err-not-member (err u105))
(define-constant err-already-paid (err u106))
(define-constant err-circle-not-active (err u107))
(define-constant err-invalid-recipient (err u108))
(define-constant err-cycle-not-complete (err u109))
(define-constant err-insufficient-funds (err u110))

(define-data-var next-circle-id uint u1)

(define-map circles
  { circle-id: uint }
  {
    name: (string-ascii 50),
    contribution-amount: uint,
    max-members: uint,
    duration-blocks: uint,
    creator: principal,
    created-at: uint,
    is-active: bool,
    current-cycle: uint,
    current-recipient-index: uint
  }
)

(define-map circle-members
  { circle-id: uint, member: principal }
  {
    joined-at: uint,
    member-index: uint,
    total-contributions: uint,
    last-contribution-cycle: uint,
    has-received-payout: bool
  }
)

(define-map circle-member-list
  { circle-id: uint, index: uint }
  { member: principal }
)

(define-map circle-stats
  { circle-id: uint }
  {
    total-members: uint,
    total-contributions: uint,
    total-payouts: uint,
    current-pot: uint,
    current-cycle-contributions: uint
  }
)

(define-map cycle-contributions
  { circle-id: uint, cycle: uint, member: principal }
  {
    amount: uint,
    contributed-at: uint
  }
)

(define-public (create-circle (name (string-ascii 50)) (contribution-amount uint) (max-members uint) (duration-blocks uint))
  (let
    (
      (circle-id (var-get next-circle-id))
    )
    (asserts! (> contribution-amount u0) err-invalid-amount)
    (asserts! (and (>= max-members u3) (<= max-members u20)) err-invalid-amount)
    (asserts! (> duration-blocks u0) err-invalid-amount)
    
    (map-set circles
      { circle-id: circle-id }
      {
        name: name,
        contribution-amount: contribution-amount,
        max-members: max-members,
        duration-blocks: duration-blocks,
        creator: tx-sender,
        created-at: stacks-block-height,
        is-active: true,
        current-cycle: u1,
        current-recipient-index: u0
      }
    )
    
    (map-set circle-stats
      { circle-id: circle-id }
      {
        total-members: u0,
        total-contributions: u0,
        total-payouts: u0,
        current-pot: u0,
        current-cycle-contributions: u0
      }
    )
    
    (var-set next-circle-id (+ circle-id u1))
    (ok circle-id)
  )
)

(define-public (join-circle (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) err-not-found))
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) err-not-found))
      (member-count (get total-members stats))
    )
    (asserts! (get is-active circle) err-circle-not-active)
    (asserts! (< member-count (get max-members circle)) err-circle-full)
    (asserts! (is-none (map-get? circle-members { circle-id: circle-id, member: tx-sender })) err-already-exists)
    
    (map-set circle-members
      { circle-id: circle-id, member: tx-sender }
      {
        joined-at: stacks-block-height,
        member-index: member-count,
        total-contributions: u0,
        last-contribution-cycle: u0,
        has-received-payout: false
      }
    )
    
    (map-set circle-member-list
      { circle-id: circle-id, index: member-count }
      { member: tx-sender }
    )
    
    (map-set circle-stats
      { circle-id: circle-id }
      (merge stats { total-members: (+ member-count u1) })
    )
    
    (ok true)
  )
)

(define-public (contribute (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) err-not-found))
      (member-data (unwrap! (map-get? circle-members { circle-id: circle-id, member: tx-sender }) err-not-member))
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) err-not-found))
      (current-cycle (get current-cycle circle))
      (contribution-amount (get contribution-amount circle))
    )
    (asserts! (get is-active circle) err-circle-not-active)
    (asserts! (is-none (map-get? cycle-contributions { circle-id: circle-id, cycle: current-cycle, member: tx-sender })) err-already-paid)
    
    (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
    
    (map-set cycle-contributions
      { circle-id: circle-id, cycle: current-cycle, member: tx-sender }
      {
        amount: contribution-amount,
        contributed-at: stacks-block-height
      }
    )
    
    (map-set circle-members
      { circle-id: circle-id, member: tx-sender }
      (merge member-data 
        {
          total-contributions: (+ (get total-contributions member-data) contribution-amount),
          last-contribution-cycle: current-cycle
        }
      )
    )
    
    (map-set circle-stats
      { circle-id: circle-id }
      (merge stats 
        {
          total-contributions: (+ (get total-contributions stats) contribution-amount),
          current-pot: (+ (get current-pot stats) contribution-amount),
          current-cycle-contributions: (+ (get current-cycle-contributions stats) u1)
        }
      )
    )
    
    (ok true)
  )
)

(define-public (distribute-payout (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) err-not-found))
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) err-not-found))
      (recipient-index (get current-recipient-index circle))
      (recipient-data (unwrap! (map-get? circle-member-list { circle-id: circle-id, index: recipient-index }) err-not-found))
      (recipient (get member recipient-data))
      (payout-amount (get current-pot stats))
      (current-cycle (get current-cycle circle))
      (total-members (get total-members stats))
      (current-cycle-contributions (get current-cycle-contributions stats))
    )
    (asserts! (get is-active circle) err-circle-not-active)
    (asserts! (> payout-amount u0) err-insufficient-funds)
    (asserts! (is-eq current-cycle-contributions total-members) err-cycle-not-complete)
    
    (try! (as-contract (stx-transfer? payout-amount tx-sender recipient)))
    
    (let
      (
        (recipient-member-data (unwrap! (map-get? circle-members { circle-id: circle-id, member: recipient }) err-not-member))
      )
      (map-set circle-members
        { circle-id: circle-id, member: recipient }
        (merge recipient-member-data { has-received-payout: true })
      )
    )
    
    (map-set circle-stats
      { circle-id: circle-id }
      (merge stats 
        {
          total-payouts: (+ (get total-payouts stats) payout-amount),
          current-pot: u0,
          current-cycle-contributions: u0
        }
      )
    )
    
    (let
      (
        (next-recipient-index (if (< (+ recipient-index u1) total-members) (+ recipient-index u1) u0))
        (next-cycle (if (is-eq next-recipient-index u0) (+ current-cycle u1) current-cycle))
      )
      (map-set circles
        { circle-id: circle-id }
        (merge circle 
          {
            current-recipient-index: next-recipient-index,
            current-cycle: next-cycle
          }
        )
      )
    )
    
    (ok recipient)
  )
)

(define-public (close-circle (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator circle)) err-owner-only)
    
    (map-set circles
      { circle-id: circle-id }
      (merge circle { is-active: false })
    )
    
    (ok true)
  )
)

(define-read-only (get-circle (circle-id uint))
  (map-get? circles { circle-id: circle-id })
)

(define-read-only (get-circle-stats (circle-id uint))
  (map-get? circle-stats { circle-id: circle-id })
)

(define-read-only (get-member-info (circle-id uint) (member principal))
  (map-get? circle-members { circle-id: circle-id, member: member })
)

(define-read-only (get-circle-member-by-index (circle-id uint) (index uint))
  (map-get? circle-member-list { circle-id: circle-id, index: index })
)

(define-read-only (get-contribution (circle-id uint) (cycle uint) (member principal))
  (map-get? cycle-contributions { circle-id: circle-id, cycle: cycle, member: member })
)

(define-read-only (check-cycle-complete (circle-id uint))
  (let
    (
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) (ok false)))
      (total-members (get total-members stats))
      (current-cycle-contributions (get current-cycle-contributions stats))
    )
    (ok (is-eq current-cycle-contributions total-members))
  )
)

(define-read-only (get-next-recipient (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) (ok none)))
      (recipient-index (get current-recipient-index circle))
    )
    (ok (map-get? circle-member-list { circle-id: circle-id, index: recipient-index }))
  )
)
