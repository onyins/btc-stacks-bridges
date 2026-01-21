;; Atomic Swap Contract
;; Implements hash time-locked contracts for trustless Bitcoin-Stacks exchanges

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SWAP-NOT-FOUND (err u101))
(define-constant ERR-INVALID-SECRET (err u102))
(define-constant ERR-SWAP-EXPIRED (err u103))
(define-constant ERR-SWAP-ALREADY-COMPLETED (err u104))
(define-constant ERR-SWAP-ALREADY-REFUNDED (err u105))
(define-constant ERR-TIMEOUT-NOT-REACHED (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-INVALID-TIMEOUT (err u108))

(define-map swaps
  { swap-id: uint }
  {
    initiator: principal,
    recipient: principal,
    amount: uint,
    hashlock: (buff 32),
    timeout-height: uint,
    completed: bool,
    refunded: bool,
    secret: (optional (buff 32))
  }
)

(define-data-var next-swap-id uint u0)
(define-data-var total-swaps-completed uint u0)
(define-data-var total-volume uint u0)

;; Read-only functions
(define-read-only (get-swap-details (swap-id uint))
  (map-get? swaps { swap-id: swap-id })
)

(define-read-only (get-total-swaps)
  (ok (var-get next-swap-id))
)

(define-read-only (get-completed-swaps)
  (ok (var-get total-swaps-completed))
)

(define-read-only (get-total-volume)
  (ok (var-get total-volume))
)

(define-read-only (is-swap-active (swap-id uint))
  (match (get-swap-details swap-id)
    swap-data (and 
      (not (get completed swap-data))
      (not (get refunded swap-data))
      (< stacks-block-height (get timeout-height swap-data))
    )
    false
  )
)

;; Public functions
(define-public (initiate-swap
  (recipient principal)
  (amount uint)
  (hashlock (buff 32))
  (timeout-blocks uint))
  (let
    (
      (swap-id (var-get next-swap-id))
      (timeout-height (+ stacks-block-height timeout-blocks))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= timeout-blocks u72) ERR-INVALID-TIMEOUT)
    (asserts! (<= timeout-blocks u1008) ERR-INVALID-TIMEOUT)
    
    (map-set swaps
      { swap-id: swap-id }
      {
        initiator: tx-sender,
        recipient: recipient,
        amount: amount,
        hashlock: hashlock,
        timeout-height: timeout-height,
        completed: false,
        refunded: false,
        secret: none
      }
    )
    
    (var-set next-swap-id (+ swap-id u1))
    (ok swap-id)
  )
)

(define-public (complete-swap
  (swap-id uint)
  (secret (buff 32)))
  (let
    (
      (swap-data (unwrap! (get-swap-details swap-id) ERR-SWAP-NOT-FOUND))
      (computed-hash (sha256 secret))
    )
    (asserts! (is-eq tx-sender (get recipient swap-data)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed swap-data)) ERR-SWAP-ALREADY-COMPLETED)
    (asserts! (not (get refunded swap-data)) ERR-SWAP-ALREADY-REFUNDED)
    (asserts! (< stacks-block-height (get timeout-height swap-data)) ERR-SWAP-EXPIRED)
    (asserts! (is-eq computed-hash (get hashlock swap-data)) ERR-INVALID-SECRET)
    
    (map-set swaps
      { swap-id: swap-id }
      (merge swap-data {
        completed: true,
        secret: (some secret)
      })
    )
    
    (var-set total-swaps-completed (+ (var-get total-swaps-completed) u1))
    (var-set total-volume (+ (var-get total-volume) (get amount swap-data)))
    (ok true)
  )
)

(define-public (refund-swap (swap-id uint))
  (let
    (
      (swap-data (unwrap! (get-swap-details swap-id) ERR-SWAP-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get initiator swap-data)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed swap-data)) ERR-SWAP-ALREADY-COMPLETED)
    (asserts! (not (get refunded swap-data)) ERR-SWAP-ALREADY-REFUNDED)
    (asserts! (>= stacks-block-height (get timeout-height swap-data)) ERR-TIMEOUT-NOT-REACHED)
    
    (map-set swaps
      { swap-id: swap-id }
      (merge swap-data { refunded: true })
    )
    
    (ok true)
  )
)

(define-public (extend-timeout
  (swap-id uint)
  (additional-blocks uint))
  (let
    (
      (swap-data (unwrap! (get-swap-details swap-id) ERR-SWAP-NOT-FOUND))
      (new-timeout (+ (get timeout-height swap-data) additional-blocks))
    )
    (asserts! (is-eq tx-sender (get initiator swap-data)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed swap-data)) ERR-SWAP-ALREADY-COMPLETED)
    (asserts! (not (get refunded swap-data)) ERR-SWAP-ALREADY-REFUNDED)
    (asserts! (< stacks-block-height (get timeout-height swap-data)) ERR-SWAP-EXPIRED)
    (asserts! (<= (- new-timeout stacks-block-height) u1008) ERR-INVALID-TIMEOUT)
    
    (map-set swaps
      { swap-id: swap-id }
      (merge swap-data { timeout-height: new-timeout })
    )
    
    (ok true)
  )
)