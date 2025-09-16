;; DataBountyHub - Marketplace for AI training data bounties
;; Researchers post bounties, contributors submit data for rewards

;; ================================
;; SECTION 1: CONSTANTS & DATA STRUCTURES
;; ================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-BOUNTY-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-BOUNTY-EXPIRED (err u103))
(define-constant ERR-ALREADY-SUBMITTED (err u104))
(define-constant ERR-INVALID-RATING (err u105))
(define-constant ERR-BOUNTY-ACTIVE (err u106))
(define-constant ERR-SUBMISSION-NOT-APPROVED (err u107))
(define-constant ERR-ALREADY-RATED (err u108))
(define-constant ERR-INVALID-CATEGORY (err u109))
(define-constant ERR-MIN-REWARD-NOT-MET (err u110))

(define-constant MIN-REWARD u1000000) ;; 1 STX minimum
(define-constant PLATFORM-FEE-PCT u5) ;; 5% platform fee
(define-constant MAX-DESCRIPTION-LENGTH u500)

(define-data-var bounty-count uint u0)
(define-data-var submission-count uint u0)
(define-data-var total-volume uint u0)
(define-data-var platform-treasury uint u0)

(define-map bounties
  { bounty-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    reward: uint,
    creator: principal,
    deadline: uint,
    completed: bool,
    data-type: (string-ascii 50),
    category: (string-ascii 30),
    created-at: uint,
    total-submissions: uint,
    featured: bool
  }
)

(define-map submissions
  { submission-id: uint }
  {
    bounty-id: uint,
    contributor: principal,
    data-hash: (buff 32),
    approved: bool,
    submitted-at: uint,
    rating: (optional uint),
    feedback: (optional (string-ascii 200))
  }
)

(define-map user-submissions
  { bounty-id: uint, contributor: principal }
  { submitted: bool }
)

(define-map user-stats
  { user: principal }
  {
    bounties-created: uint,
    submissions-made: uint,
    total-earned: uint,
    total-spent: uint,
    average-rating: uint,
    reputation-score: uint
  }
)

;; Create a new data bounty with enhanced features
(define-public (create-bounty 
  (title (string-ascii 100)) 
  (description (string-ascii 500))
  (reward uint)
  (duration uint)
  (data-type (string-ascii 50))
  (category (string-ascii 30)))
  (let
    (
      (bounty-id (+ (var-get bounty-count) u1))
      (deadline (+ block-height duration))
      (platform-fee (/ (* reward PLATFORM-FEE-PCT) u100))
      (total-cost (+ reward platform-fee))
    )
    (asserts! (>= reward MIN-REWARD) ERR-MIN-REWARD-NOT-MET)
    (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
    
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    (var-set platform-treasury (+ (var-get platform-treasury) platform-fee))
    
    (map-set bounties
      { bounty-id: bounty-id }
      {
        title: title,
        description: description,
        reward: reward,
        creator: tx-sender,
        deadline: deadline,
        completed: false,
        data-type: data-type,
        category: category,
        created-at: block-height,
        total-submissions: u0,
        featured: false
      }
    )
    
    (update-user-stats-bounty-created tx-sender reward)
    (var-set bounty-count bounty-id)
    (var-set total-volume (+ (var-get total-volume) reward))
    (ok bounty-id)
  )
)

;; Submit data for a bounty with enhanced validation
(define-public (submit-data (bounty-id uint) (data-hash (buff 32)))
  (let
    (
      (bounty (unwrap! (map-get? bounties { bounty-id: bounty-id }) ERR-BOUNTY-NOT-FOUND))
      (submission-id (+ (var-get submission-count) u1))
      (existing-submission (map-get? user-submissions { bounty-id: bounty-id, contributor: tx-sender }))
    )
    (asserts! (< block-height (get deadline bounty)) ERR-BOUNTY-EXPIRED)
    (asserts! (not (get completed bounty)) ERR-BOUNTY-NOT-FOUND)
    (asserts! (is-none existing-submission) ERR-ALREADY-SUBMITTED)
    
    (map-set submissions
      { submission-id: submission-id }
      {
        bounty-id: bounty-id,
        contributor: tx-sender,
        data-hash: data-hash,
        approved: false,
        submitted-at: block-height,
        rating: none,
        feedback: none
      }
    )
    
    (map-set user-submissions
      { bounty-id: bounty-id, contributor: tx-sender }
      { submitted: true }
    )
    
    ;; Update bounty submission count
    (map-set bounties
      { bounty-id: bounty-id }
      (merge bounty { total-submissions: (+ (get total-submissions bounty) u1) })
    )
    
    (update-user-stats-submission-made tx-sender)
    (var-set submission-count submission-id)
    (ok submission-id)
  )
)

;; Cancel bounty (only if no approved submissions)
(define-public (cancel-bounty (bounty-id uint))
  (let
    (
      (bounty (unwrap! (map-get? bounties { bounty-id: bounty-id }) ERR-BOUNTY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator bounty)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed bounty)) ERR-BOUNTY-NOT-FOUND)
    
    ;; Refund the reward
    (try! (as-contract (stx-transfer? (get reward bounty) tx-sender (get creator bounty))))
    
    (map-set bounties
      { bounty-id: bounty-id }
      (merge bounty { completed: true })
    )
    
    (ok true)
  )
)

;; Approve submission and pay reward with rating
(define-public (approve-submission (submission-id uint) (rating uint) (feedback (optional (string-ascii 200))))
  (let
    (
      (submission (unwrap! (map-get? submissions { submission-id: submission-id }) ERR-BOUNTY-NOT-FOUND))
      (bounty (unwrap! (map-get? bounties { bounty-id: (get bounty-id submission) }) ERR-BOUNTY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator bounty)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get approved submission)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed bounty)) ERR-BOUNTY-NOT-FOUND)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    
    (try! (as-contract (stx-transfer? (get reward bounty) tx-sender (get contributor submission))))
    
    (map-set submissions
      { submission-id: submission-id }
      (merge submission { 
        approved: true, 
        rating: (some rating),
        feedback: feedback
      })
    )
    
    (map-set bounties
      { bounty-id: (get bounty-id submission) }
      (merge bounty { completed: true })
    )
    
    (update-user-stats-earned (get contributor submission) (get reward bounty) rating)
    (ok true)
  )
)

;; Reject submission with feedback
(define-public (reject-submission (submission-id uint) (feedback (string-ascii 200)))
  (let
    (
      (submission (unwrap! (map-get? submissions { submission-id: submission-id }) ERR-BOUNTY-NOT-FOUND))
      (bounty (unwrap! (map-get? bounties { bounty-id: (get bounty-id submission) }) ERR-BOUNTY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator bounty)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get approved submission)) ERR-NOT-AUTHORIZED)
    
    (map-set submissions
      { submission-id: submission-id }
      (merge submission { feedback: (some feedback) })
    )
    
    (ok true)
  )
)

;; Rate a completed submission (additional rating system)
(define-public (rate-submission (submission-id uint) (rating uint))
  (let
    (
      (submission (unwrap! (map-get? submissions { submission-id: submission-id }) ERR-BOUNTY-NOT-FOUND))
      (bounty (unwrap! (map-get? bounties { bounty-id: (get bounty-id submission) }) ERR-BOUNTY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator bounty)) ERR-NOT-AUTHORIZED)
    (asserts! (get approved submission) ERR-SUBMISSION-NOT-APPROVED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    (asserts! (is-none (get rating submission)) ERR-ALREADY-RATED)
    
    (map-set submissions
      { submission-id: submission-id }
      (merge submission { rating: (some rating) })
    )
    
    (ok true)
  )
)