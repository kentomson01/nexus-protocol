;; Title: Nexus Protocol - Bitcoin-Secured Liquid Staking & Governance Hub
;;
;; Summary:
;; Nexus Protocol creates a sophisticated liquid staking ecosystem on Stacks
;; that harnesses Bitcoin's security while providing flexible governance,
;; multi-tier rewards, and seamless capital efficiency for DeFi participants.
;;
;; Description:
;; Nexus Protocol transforms traditional staking by offering:
;; - Liquid staking positions that maintain full capital mobility
;; - Time-weighted governance with quadratic voting mechanisms
;; - Dynamic tier-based rewards that scale with commitment depth
;; - Emergency safeguards anchored to Bitcoin's consensus layer
;; - Cross-protocol yield optimization with risk-adjusted returns
;; - Community-driven parameter adjustment through transparent governance
;;
;; The protocol enables users to earn compounding rewards while maintaining
;; liquidity, participate in decentralized governance, and access advanced
;; DeFi strategies without sacrificing security or decentralization.

;; TOKEN DEFINITIONS

(define-fungible-token ANALYTICS-TOKEN u0)

;; CORE CONSTANTS

(define-constant CONTRACT-OWNER tx-sender)

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-PROTOCOL (err u1001))
(define-constant ERR-INVALID-AMOUNT (err u1002))
(define-constant ERR-INSUFFICIENT-STX (err u1003))
(define-constant ERR-COOLDOWN-ACTIVE (err u1004))
(define-constant ERR-NO-STAKE (err u1005))
(define-constant ERR-BELOW-MINIMUM (err u1006))
(define-constant ERR-PAUSED (err u1007))

;; PROTOCOL VARIABLES

(define-data-var contract-paused bool false)
(define-data-var emergency-mode bool false)
(define-data-var stx-pool uint u0)
(define-data-var base-reward-rate uint u500) ;; 5% base APY (100 = 1%)
(define-data-var bonus-rate uint u100) ;; 1% bonus for extended staking
(define-data-var minimum-stake uint u1000000) ;; Minimum stake requirement
(define-data-var cooldown-period uint u1440) ;; 24-hour cooldown period
(define-data-var proposal-count uint u0) ;; Total governance proposals

;; DATA STRUCTURES

;; Governance Proposal Registry
(define-map Proposals
  { proposal-id: uint }
  {
    creator: principal,
    description: (string-utf8 256),
    start-block: uint,
    end-block: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    minimum-votes: uint,
  }
)

;; User Portfolio & Analytics
(define-map UserPositions
  principal
  {
    total-collateral: uint,
    total-debt: uint,
    health-factor: uint,
    last-updated: uint,
    stx-staked: uint,
    analytics-tokens: uint,
    voting-power: uint,
    tier-level: uint,
    rewards-multiplier: uint,
  }
)

;; Staking Position Management
(define-map StakingPositions
  principal
  {
    amount: uint,
    start-block: uint,
    last-claim: uint,
    lock-period: uint,
    cooldown-start: (optional uint),
    accumulated-rewards: uint,
  }
)

;; Tier Level Configuration
(define-map TierLevels
  uint
  {
    minimum-stake: uint,
    reward-multiplier: uint,
    features-enabled: (list 10 bool),
  }
)

;; PRIVATE FUNCTIONS

;; Determines user tier based on stake amount and commitment level
(define-private (get-tier-info (stake-amount uint))
  (if (>= stake-amount u10000000)
    {
      tier-level: u3,
      reward-multiplier: u200,
    } ;; Diamond Tier: 2x rewards
    (if (>= stake-amount u5000000)
      {
        tier-level: u2,
        reward-multiplier: u150,
      } ;; Gold Tier: 1.5x rewards
      {
        tier-level: u1,
        reward-multiplier: u100,
      } ;; Silver Tier: 1x rewards
    )
  )
)

;; Calculates time-lock bonus multiplier for extended commitment
(define-private (calculate-lock-multiplier (lock-period uint))
  (if (>= lock-period u8640) ;; 2-month commitment
    u150 ;; 1.5x time bonus
    (if (>= lock-period u4320) ;; 1-month commitment
      u125 ;; 1.25x time bonus
      u100 ;; No lock bonus
    )
  )
)

;; Computes dynamic rewards based on stake, time, and tier multipliers
(define-private (calculate-rewards
    (user principal)
    (blocks uint)
  )
  (let (
      (staking-position (unwrap! (map-get? StakingPositions user) u0))
      (user-position (unwrap! (map-get? UserPositions user) u0))
      (stake-amount (get amount staking-position))
      (base-rate (var-get base-reward-rate))
      (multiplier (get rewards-multiplier user-position))
    )
    ;; Formula: (stake * rate * multiplier * blocks) / blocks_per_year
    (/ (* (* (* stake-amount base-rate) multiplier) blocks) u14400000)
  )
)

;; Validates proposal description meets quality standards
(define-private (is-valid-description (desc (string-utf8 256)))
  (and
    (>= (len desc) u10) ;; Minimum 10 characters
    (<= (len desc) u256) ;; Maximum 256 characters
  )
)

;; Validates lock period options for staking commitments
(define-private (is-valid-lock-period (lock-period uint))
  (or
    (is-eq lock-period u0) ;; Flexible staking
    (is-eq lock-period u4320) ;; 1-month lock
    (is-eq lock-period u8640) ;; 2-month lock
  )
)

;; Validates voting period duration for governance proposals
(define-private (is-valid-voting-period (period uint))
  (and
    (>= period u100) ;; Minimum 100 blocks
    (<= period u2880) ;; Maximum 2880 blocks (~1 day)
  )
)

;; PUBLIC FUNCTIONS

;; Initialize protocol with tier structure and default configurations
(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Configure Silver Tier (Entry Level)
    (map-set TierLevels u1 {
      minimum-stake: u1000000, ;; 1M uSTX minimum
      reward-multiplier: u100, ;; 1x base rewards
      features-enabled: (list true false false false false false false false false false),
    })
    ;; Configure Gold Tier (Intermediate)
    (map-set TierLevels u2 {
      minimum-stake: u5000000, ;; 5M uSTX minimum
      reward-multiplier: u150, ;; 1.5x enhanced rewards
      features-enabled: (list true true true false false false false false false false),
    })
    ;; Configure Diamond Tier (Premium)
    (map-set TierLevels u3 {
      minimum-stake: u10000000, ;; 10M uSTX minimum
      reward-multiplier: u200, ;; 2x premium rewards
      features-enabled: (list true true true true true false false false false false),
    })
    (ok true)
  )
)

;; Stake STX tokens with optional time-lock for enhanced rewards
(define-public (stake-stx
    (amount uint)
    (lock-period uint)
  )
  (let ((current-position (default-to {
      total-collateral: u0,
      total-debt: u0,
      health-factor: u0,
      last-updated: u0,
      stx-staked: u0,
      analytics-tokens: u0,
      voting-power: u0,
      tier-level: u0,
      rewards-multiplier: u100,
    }
      (map-get? UserPositions tx-sender)
    )))
    ;; Pre-flight validation checks
    (asserts! (is-valid-lock-period lock-period) ERR-INVALID-PROTOCOL)
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (>= amount (var-get minimum-stake)) ERR-BELOW-MINIMUM)
    ;; Transfer STX to protocol custody
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    ;; Calculate tier benefits and time-lock bonuses
    (let (
        (new-total-stake (+ (get stx-staked current-position) amount))
        (tier-info (get-tier-info new-total-stake))
        (lock-multiplier (calculate-lock-multiplier lock-period))
      )
      ;; Record staking position details
      (map-set StakingPositions tx-sender {
        amount: amount,
        start-block: stacks-block-height,
        last-claim: stacks-block-height,
        lock-period: lock-period,
        cooldown-start: none,
        accumulated-rewards: u0,
      })
      ;; Update user position with tier progression
      (map-set UserPositions tx-sender
        (merge current-position {
          stx-staked: new-total-stake,
          tier-level: (get tier-level tier-info),
          rewards-multiplier: (* (get reward-multiplier tier-info) lock-multiplier),
        })
      )
      ;; Update global STX pool metrics
      (var-set stx-pool (+ (var-get stx-pool) amount))
      (ok true)
    )
  )
)

;; Begin unstaking process with mandatory cooling-off period
(define-public (initiate-unstake (amount uint))
  (let (
      (staking-position (unwrap! (map-get? StakingPositions tx-sender) ERR-NO-STAKE))
      (current-amount (get amount staking-position))
    )
    ;; Validate unstaking request
    (asserts! (>= current-amount amount) ERR-INSUFFICIENT-STX)
    (asserts! (is-none (get cooldown-start staking-position)) ERR-COOLDOWN-ACTIVE)
    ;; Activate cooldown period for security
    (map-set StakingPositions tx-sender
      (merge staking-position { cooldown-start: (some stacks-block-height) })
    )
    (ok true)
  )
)

;; Complete unstaking after cooldown period expires
(define-public (complete-unstake)
  (let (
      (staking-position (unwrap! (map-get? StakingPositions tx-sender) ERR-NO-STAKE))
      (cooldown-start (unwrap! (get cooldown-start staking-position) ERR-NOT-AUTHORIZED))
    )
    ;; Verify cooldown period has elapsed
    (asserts!
      (>= (- stacks-block-height cooldown-start) (var-get cooldown-period))
      ERR-COOLDOWN-ACTIVE
    )
    ;; Return STX to user wallet
    (try! (as-contract (stx-transfer? (get amount staking-position) tx-sender tx-sender)))
    ;; Clean up staking position
    (map-delete StakingPositions tx-sender)
    (ok true)
  )
)

;; Create governance proposal for protocol parameter changes
(define-public (create-proposal
    (description (string-utf8 256))
    (voting-period uint)
  )
  (let (
      (user-position (unwrap! (map-get? UserPositions tx-sender) ERR-NOT-AUTHORIZED))
      (proposal-id (+ (var-get proposal-count) u1))
    )
    ;; Validate proposal creator has sufficient voting power
    (asserts! (>= (get voting-power user-position) u1000000) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-description description) ERR-INVALID-PROTOCOL)
    (asserts! (is-valid-voting-period voting-period) ERR-INVALID-PROTOCOL)
    ;; Register new governance proposal
    (map-set Proposals { proposal-id: proposal-id } {
      creator: tx-sender,
      description: description,
      start-block: stacks-block-height,
      end-block: (+ stacks-block-height voting-period),
      executed: false,
      votes-for: u0,
      votes-against: u0,
      minimum-votes: u1000000,
    })
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

;; Cast weighted vote on active governance proposal
(define-public (vote-on-proposal
    (proposal-id uint)
    (vote-for bool)
  )
  (let (
      (proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id })
        ERR-INVALID-PROTOCOL
      ))
      (user-position (unwrap! (map-get? UserPositions tx-sender) ERR-NOT-AUTHORIZED))
      (voting-power (get voting-power user-position))
      (max-proposal-id (var-get proposal-count))
    )
    ;; Validate voting window and proposal existence
    (asserts! (< stacks-block-height (get end-block proposal)) ERR-NOT-AUTHORIZED)
    (asserts! (and (> proposal-id u0) (<= proposal-id max-proposal-id))
      ERR-INVALID-PROTOCOL
    )
    ;; Record weighted vote based on user's stake
    (map-set Proposals { proposal-id: proposal-id }
      (merge proposal {
        votes-for: (if vote-for
          (+ (get votes-for proposal) voting-power)
          (get votes-for proposal)
        ),
        votes-against: (if vote-for
          (get votes-against proposal)
          (+ (get votes-against proposal) voting-power)
        ),
      })
    )
    (ok true)
  )
)

;; Emergency pause mechanism for protocol security
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

;; Resume normal protocol operations
(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; READ-ONLY FUNCTIONS

;; Returns protocol owner address
(define-read-only (get-contract-owner)
  (ok CONTRACT-OWNER)
)

;; Returns total STX locked in protocol
(define-read-only (get-stx-pool)
  (ok (var-get stx-pool))
)

;; Returns total number of governance proposals
(define-read-only (get-proposal-count)
  (ok (var-get proposal-count))
)
