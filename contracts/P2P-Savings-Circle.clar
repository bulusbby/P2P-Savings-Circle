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
(define-constant err-emergency-not-triggered (err u111))
(define-constant err-already-withdrawn (err u112))
(define-constant err-low-reputation (err u113))
(define-constant err-reputation-exists (err u114))

(define-constant base-reputation u100)
(define-constant max-reputation u1000)
(define-constant min-reputation u0)
(define-constant on-time-bonus u10)
(define-constant late-penalty u15)
(define-constant completion-bonus u50)
(define-constant high-reputation-threshold u500)

(define-data-var next-circle-id uint u1)

(define-map member-reputation
  { member: principal }
  {
    reputation-score: uint,
    circles-completed: uint,
    circles-defaulted: uint,
    total-contributions: uint,
    on-time-contributions: uint,
    last-updated: uint
  }
)

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
    current-recipient-index: uint,
    emergency-triggered: bool,
    emergency-trigger-height: uint
  }
)

(define-map circle-members
  { circle-id: uint, member: principal }
  {
    joined-at: uint,
    member-index: uint,
    total-contributions: uint,
    last-contribution-cycle: uint,
    has-received-payout: bool,
    emergency-withdrawn: bool
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
        current-recipient-index: u0,
        emergency-triggered: false,
        emergency-trigger-height: u0
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

(define-public (create-priority-circle (name (string-ascii 50)) (contribution-amount uint) (max-members uint) (duration-blocks uint))
  (let
    (
      (circle-id (var-get next-circle-id))
      (is-high-rep (is-high-reputation-member tx-sender))
    )
    (asserts! (> contribution-amount u0) err-invalid-amount)
    (asserts! (and (>= max-members u3) (<= max-members u20)) err-invalid-amount)
    (asserts! (> duration-blocks u0) err-invalid-amount)
    (asserts! is-high-rep err-low-reputation)
    
    (let
      (
        (discounted-amount (/ (* contribution-amount u90) u100))
      )
      (map-set circles
        { circle-id: circle-id }
        {
          name: name,
          contribution-amount: discounted-amount,
          max-members: max-members,
          duration-blocks: duration-blocks,
          creator: tx-sender,
          created-at: stacks-block-height,
          is-active: true,
          current-cycle: u1,
          current-recipient-index: u0,
          emergency-triggered: false,
          emergency-trigger-height: u0
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
    
    (match (map-get? member-reputation { member: tx-sender })
      some-rep true
      (try! (initialize-reputation tx-sender))
    )
    
    (map-set circle-members
      { circle-id: circle-id, member: tx-sender }
      {
        joined-at: stacks-block-height,
        member-index: member-count,
        total-contributions: u0,
        last-contribution-cycle: u0,
        has-received-payout: false,
        emergency-withdrawn: false
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
    
    (let
      (
        (actual-amount (unwrap! (get-contribution-amount-with-reputation circle-id tx-sender) err-invalid-amount))
        (circle-start-height (get created-at circle))
        (cycle-expected-height (+ circle-start-height (* (- current-cycle u1) (get duration-blocks circle))))
        (is-on-time (<= stacks-block-height (+ cycle-expected-height u144)))
      )
      (try! (stx-transfer? actual-amount tx-sender (as-contract tx-sender)))
      
      (unwrap! (update-reputation-score tx-sender 
                                       (if is-on-time (to-int on-time-bonus) (- (to-int late-penalty))) 
                                       u1 
                                       is-on-time) err-invalid-amount)
      
      (map-set cycle-contributions
        { circle-id: circle-id, cycle: current-cycle, member: tx-sender }
        {
          amount: actual-amount,
          contributed-at: stacks-block-height
        }
      )
      
      (map-set circle-members
        { circle-id: circle-id, member: tx-sender }
        (merge member-data 
          {
            total-contributions: (+ (get total-contributions member-data) actual-amount),
            last-contribution-cycle: current-cycle
          }
        )
      )
      
      (map-set circle-stats
        { circle-id: circle-id }
        (merge stats 
          {
            total-contributions: (+ (get total-contributions stats) actual-amount),
            current-pot: (+ (get current-pot stats) actual-amount),
            current-cycle-contributions: (+ (get current-cycle-contributions stats) u1)
          }
        )
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

(define-public (initialize-reputation (member principal))
  (let
    (
      (existing-rep (map-get? member-reputation { member: member }))
    )
    (asserts! (is-none existing-rep) err-reputation-exists)
    
    (map-set member-reputation
      { member: member }
      {
        reputation-score: base-reputation,
        circles-completed: u0,
        circles-defaulted: u0,
        total-contributions: u0,
        on-time-contributions: u0,
        last-updated: stacks-block-height
      }
    )
    
    (ok true)
  )
)

(define-private (update-reputation-score (member principal) (score-change int) (contribution-update uint) (on-time bool))
  (let
    (
      (current-rep (default-to 
        {
          reputation-score: base-reputation,
          circles-completed: u0,
          circles-defaulted: u0,
          total-contributions: u0,
          on-time-contributions: u0,
          last-updated: stacks-block-height
        }
        (map-get? member-reputation { member: member })
      ))
      (current-score (get reputation-score current-rep))
      (new-score-raw (if (>= score-change 0)
                       (+ current-score (to-uint score-change))
                       (if (>= current-score (to-uint (- score-change)))
                         (- current-score (to-uint (- score-change)))
                         min-reputation)))
      (new-score (if (> new-score-raw max-reputation) max-reputation new-score-raw))
    )
    (map-set member-reputation
      { member: member }
      (merge current-rep 
        {
          reputation-score: new-score,
          total-contributions: (+ (get total-contributions current-rep) contribution-update),
          on-time-contributions: (if on-time 
                                   (+ (get on-time-contributions current-rep) u1)
                                   (get on-time-contributions current-rep)),
          last-updated: stacks-block-height
        }
      )
    )
    (ok new-score)
  )
)

(define-private (mark-circle-completion (member principal) (completed bool))
  (let
    (
      (current-rep (default-to 
        {
          reputation-score: base-reputation,
          circles-completed: u0,
          circles-defaulted: u0,
          total-contributions: u0,
          on-time-contributions: u0,
          last-updated: stacks-block-height
        }
        (map-get? member-reputation { member: member })
      ))
    )
    (map-set member-reputation
      { member: member }
      (merge current-rep 
        {
          circles-completed: (if completed 
                               (+ (get circles-completed current-rep) u1)
                               (get circles-completed current-rep)),
          circles-defaulted: (if (not completed) 
                               (+ (get circles-defaulted current-rep) u1)
                               (get circles-defaulted current-rep)),
          last-updated: stacks-block-height
        }
      )
    )
    (if completed
      (update-reputation-score member (to-int completion-bonus) u0 false)
      (update-reputation-score member (- (to-int late-penalty)) u0 false)
    )
  )
)

(define-read-only (get-member-reputation (member principal))
  (map-get? member-reputation { member: member })
)

(define-read-only (is-high-reputation-member (member principal))
  (let
    (
      (rep-data (map-get? member-reputation { member: member }))
    )
    (match rep-data
      some-rep (>= (get reputation-score some-rep) high-reputation-threshold)
      false
    )
  )
)

(define-read-only (get-contribution-amount-with-reputation (circle-id uint) (member principal))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) (ok u0)))
      (base-amount (get contribution-amount circle))
      (is-high-rep (is-high-reputation-member member))
    )
    (if is-high-rep
      (ok (/ (* base-amount u95) u100))
      (ok base-amount)
    )
  )
)

(define-public (trigger-emergency-exit (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) err-not-found))
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator circle)) err-owner-only)
    (asserts! (get is-active circle) err-circle-not-active)
    (asserts! (not (get emergency-triggered circle)) err-already-exists)
    
    (map-set circles
      { circle-id: circle-id }
      (merge circle 
        {
          emergency-triggered: true,
          emergency-trigger-height: stacks-block-height,
          is-active: false
        }
      )
    )
    
    (ok true)
  )
)

(define-public (emergency-withdraw (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) err-not-found))
      (member-data (unwrap! (map-get? circle-members { circle-id: circle-id, member: tx-sender }) err-not-member))
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) err-not-found))
      (total-contributions (get total-contributions member-data))
      (emergency-wait-blocks u144)
      (current-height stacks-block-height)
      (trigger-height (get emergency-trigger-height circle))
    )
    (asserts! (get emergency-triggered circle) err-emergency-not-triggered)
    (asserts! (not (get emergency-withdrawn member-data)) err-already-withdrawn)
    (asserts! (> total-contributions u0) err-invalid-amount)
    (asserts! (>= (- current-height trigger-height) emergency-wait-blocks) err-emergency-not-triggered)
    
    (let
      (
        (total-pool (get total-contributions stats))
        (current-pot (get current-pot stats))
        (member-share (if (> total-pool u0) 
                       (/ (* total-contributions current-pot) total-pool)
                       u0))
      )
      (asserts! (> member-share u0) err-insufficient-funds)
      
      (try! (as-contract (stx-transfer? member-share tx-sender tx-sender)))
      
      (map-set circle-members
        { circle-id: circle-id, member: tx-sender }
        (merge member-data { emergency-withdrawn: true })
      )
      
      (map-set circle-stats
        { circle-id: circle-id }
        (merge stats { current-pot: (- current-pot member-share) })
      )
      
      (ok member-share)
    )
  )
)

(define-read-only (get-emergency-withdrawal-amount (circle-id uint) (member principal))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) (ok u0)))
      (member-data (unwrap! (map-get? circle-members { circle-id: circle-id, member: member }) (ok u0)))
      (stats (unwrap! (map-get? circle-stats { circle-id: circle-id }) (ok u0)))
      (total-contributions (get total-contributions member-data))
    )
    (if (get emergency-triggered circle)
      (let
        (
          (total-pool (get total-contributions stats))
          (current-pot (get current-pot stats))
        )
        (if (and (> total-pool u0) (> total-contributions u0))
          (ok (/ (* total-contributions current-pot) total-pool))
          (ok u0)
        )
      )
      (ok u0)
    )
  )
)

(define-read-only (can-emergency-withdraw (circle-id uint) (member principal))
  (let
    (
      (circle (unwrap! (map-get? circles { circle-id: circle-id }) (ok false)))
      (member-data (unwrap! (map-get? circle-members { circle-id: circle-id, member: member }) (ok false)))
      (emergency-wait-blocks u144)
      (current-height stacks-block-height)
      (trigger-height (get emergency-trigger-height circle))
    )
    (ok (and
      (get emergency-triggered circle)
      (not (get emergency-withdrawn member-data))
      (> (get total-contributions member-data) u0)
      (>= (- current-height trigger-height) emergency-wait-blocks)
    ))
  )
)
