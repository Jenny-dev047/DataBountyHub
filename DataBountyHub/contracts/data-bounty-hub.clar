;; DataBountyHub - Marketplace for AI training data bounties
;; Researchers post bounties, contributors submit data for rewards

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
      (deadline (+ stacks-block-height duration))
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
        created-at: stacks-block-height,
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
    (asserts! (< stacks-block-height (get deadline bounty)) ERR-BOUNTY-EXPIRED)
    (asserts! (not (get completed bounty)) ERR-BOUNTY-NOT-FOUND)
    (asserts! (is-none existing-submission) ERR-ALREADY-SUBMITTED)
    
    (map-set submissions
      { submission-id: submission-id }
      {
        bounty-id: bounty-id,
        contributor: tx-sender,
        data-hash: data-hash,
        approved: false,
        submitted-at: stacks-block-height,
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

;; Get bounty details
(define-read-only (get-bounty (bounty-id uint))
  (map-get? bounties { bounty-id: bounty-id })
)

;; Get submission details
(define-read-only (get-submission (submission-id uint))
  (map-get? submissions { submission-id: submission-id })
)

;; Check if user has submitted to bounty
(define-read-only (has-submitted (bounty-id uint) (contributor principal))
  (default-to { submitted: false } (map-get? user-submissions { bounty-id: bounty-id, contributor: contributor }))
)

;; Get total bounties count
(define-read-only (get-bounty-count)
  (var-get bounty-count)
)

;; Get total submissions count
(define-read-only (get-submission-count)
  (var-get submission-count)
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-bounties: (var-get bounty-count),
    total-submissions: (var-get submission-count),
    total-volume: (var-get total-volume),
    platform-treasury: (var-get platform-treasury)
  }
)

;; Get user statistics
(define-read-only (get-user-stats (user principal))
  (default-to 
    {
      bounties-created: u0,
      submissions-made: u0,
      total-earned: u0,
      total-spent: u0,
      average-rating: u0,
      reputation-score: u0
    }
    (map-get? user-stats { user: user })
  )
)

;; Get bounties by category
(define-read-only (get-bounties-by-category (category (string-ascii 30)))
  ;; This would return a list in a full implementation
  ;; For now, returns if category is valid
  (is-valid-category category)
)

;; Check if bounty is active (not completed and not expired)
(define-read-only (is-bounty-active (bounty-id uint))
  (match (map-get? bounties { bounty-id: bounty-id })
    bounty (and 
      (not (get completed bounty))
      (< stacks-block-height (get deadline bounty))
    )
    false
  )
)

;; Admin function to feature/unfeature bounties
(define-public (set-bounty-featured (bounty-id uint) (featured bool))
  (let
    (
      (bounty (unwrap! (map-get? bounties { bounty-id: bounty-id }) ERR-BOUNTY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set bounties
      { bounty-id: bounty-id }
      (merge bounty { featured: featured })
    )
    
    (ok true)
  )
)

;; Admin function to withdraw platform fees
(define-public (withdraw-platform-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= amount (var-get platform-treasury)) ERR-INSUFFICIENT-FUNDS)
    
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (var-set platform-treasury (- (var-get platform-treasury) amount))
    
    (ok true)
  )
)

;; Update user statistics when creating bounty
(define-private (update-user-stats-bounty-created (user principal) (amount uint))
  (let
    (
      (current-stats (get-user-stats user))
    )
    (map-set user-stats
      { user: user }
      (merge current-stats {
        bounties-created: (+ (get bounties-created current-stats) u1),
        total-spent: (+ (get total-spent current-stats) amount)
      })
    )
  )
)

;; Update user statistics when making submission
(define-private (update-user-stats-submission-made (user principal))
  (let
    (
      (current-stats (get-user-stats user))
    )
    (map-set user-stats
      { user: user }
      (merge current-stats {
        submissions-made: (+ (get submissions-made current-stats) u1)
      })
    )
  )
)

;; Update user statistics when earning from approved submission
(define-private (update-user-stats-earned (user principal) (amount uint) (rating uint))
  (let
    (
      (current-stats (get-user-stats user))
      (current-submission-count (get submissions-made current-stats))
      (current-avg (get average-rating current-stats))
      (new-avg (if (is-eq current-avg u0)
                 rating
                 (/ (+ (* current-avg current-submission-count) rating) (+ current-submission-count u1))
               ))
      (new-reputation (calculate-reputation-score 
                        (+ (get total-earned current-stats) amount)
                        new-avg
                        (+ current-submission-count u1)
                      ))
    )
    (map-set user-stats
      { user: user }
      (merge current-stats {
        total-earned: (+ (get total-earned current-stats) amount),
        average-rating: new-avg,
        reputation-score: new-reputation
      })
    )
  )
)

;; Calculate reputation score based on earnings, ratings, and activity
(define-private (calculate-reputation-score (total-earned uint) (avg-rating uint) (user-submission-count uint))
  (let
    (
      (earning-factor (/ total-earned u1000000)) ;; Divide by 1 STX for scaling
      (rating-factor (* avg-rating u10))
      (activity-factor (if (<= user-submission-count u50) user-submission-count u50)) ;; Cap at 50 for diminishing returns
    )
    (+ earning-factor rating-factor activity-factor)
  )
)

;; Validate category
(define-private (is-valid-category (category (string-ascii 30)))
  (or
    (is-eq category "computer-vision")
    (is-eq category "natural-language")
    (is-eq category "audio-processing")
    (is-eq category "structured-data")
    (is-eq category "multimodal")
    (is-eq category "other")
  )
)