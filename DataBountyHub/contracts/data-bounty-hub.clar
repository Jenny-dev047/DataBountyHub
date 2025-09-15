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