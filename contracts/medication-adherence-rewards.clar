;; Medication Adherence Rewards Smart Contract
;; Token rewards for consistent medication adherence and caregivers supporting elderly health

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u400))
(define-constant ERR-PATIENT-NOT-FOUND (err u401))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-INVALID-AMOUNT (err u403))
(define-constant ERR-REWARD-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-CLAIMED (err u405))
(define-constant ERR-MILESTONE-NOT-REACHED (err u406))
(define-constant ERR-INVALID-PERIOD (err u407))

;; Reward Types
(define-constant REWARD-DAILY-ADHERENCE u1)
(define-constant REWARD-WEEKLY-STREAK u2)
(define-constant REWARD-MONTHLY-PERFECT u3)
(define-constant REWARD-CAREGIVER-SUPPORT u4)
(define-constant REWARD-MILESTONE-ACHIEVEMENT u5)

;; Token amounts
(define-constant DAILY-REWARD u10)
(define-constant WEEKLY-STREAK-REWARD u100)
(define-constant MONTHLY-PERFECT-REWARD u500)
(define-constant CAREGIVER-SUPPORT-REWARD u50)
(define-constant MILESTONE-BASE-REWARD u200)

;; Data Structures
(define-map adherence-records
    { patient: principal, date: uint }
    {
        medications-taken: uint,
        medications-scheduled: uint,
        adherence-percentage: uint,
        bonus-eligible: bool,
        recorded-by: principal,
        notes: (optional (string-utf8 200))
    }
)

(define-map reward-balances
    principal
    {
        total-earned: uint,
        total-redeemed: uint,
        current-balance: uint,
        streak-days: uint,
        last-reward-date: uint,
        milestone-level: uint
    }
)

(define-map reward-history
    uint ;; reward-id
    {
        recipient: principal,
        reward-type: uint,
        amount: uint,
        reason: (string-utf8 200),
        awarded-date: uint,
        awarded-by: principal,
        claimed: bool,
        claimed-date: (optional uint)
    }
)

(define-map caregiver-contributions
    { patient: principal, caregiver: principal, period: uint }
    {
        support-actions: uint,
        reminder-assists: uint,
        medication-helps: uint,
        emotional-support: uint,
        total-contribution-score: uint,
        reward-earned: uint,
        period-start: uint,
        period-end: uint
    }
)

(define-map milestone-definitions
    uint ;; milestone-id
    {
        title: (string-utf8 100),
        description: (string-utf8 300),
        requirement-type: (string-utf8 50),
        requirement-value: uint,
        reward-multiplier: uint,
        badge-earned: (string-utf8 100),
        active: bool
    }
)

(define-map patient-milestones
    { patient: principal, milestone-id: uint }
    {
        achieved: bool,
        achieved-date: (optional uint),
        progress-value: uint,
        reward-claimed: bool
    }
)

(define-map redemption-options
    uint ;; option-id
    {
        title: (string-utf8 150),
        description: (string-utf8 300),
        cost: uint,
        category: (string-utf8 50),
        available: bool,
        provider: (optional (string-utf8 100))
    }
)

;; Data Variables
(define-data-var next-reward-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var next-option-id uint u1)
(define-data-var total-rewards-distributed uint u0)
(define-data-var total-tokens-issued uint u0)
(define-data-var contract-token-reserve uint u1000000) ;; Starting reserve

;; Private Functions
(define-private (is-authorized-recorder (patient principal) (recorder principal))
    (or 
        (is-eq recorder patient)
        (is-eq recorder CONTRACT-OWNER)
        ;; In practice, would check caregiver permissions from coordination contract
        true
    )
)

(define-private (get-current-time)
    burn-block-height
)

(define-private (calculate-adherence-percentage (taken uint) (scheduled uint))
    (if (is-eq scheduled u0)
        u0
        (/ (* taken u100) scheduled)
    )
)

(define-private (is-perfect-adherence (percentage uint))
    (>= percentage u100)
)

(define-private (calculate-streak-bonus (streak-days uint))
    (if (>= streak-days u7)
        (if (>= streak-days u30)
            (* WEEKLY-STREAK-REWARD u4) ;; Monthly bonus
            WEEKLY-STREAK-REWARD
        )
        u0
    )
)

(define-private (update-patient-balance (patient principal) (amount uint) (reward-type uint))
    (let 
        ((current-balance (default-to { total-earned: u0, total-redeemed: u0, current-balance: u0, streak-days: u0, last-reward-date: u0, milestone-level: u0 } (map-get? reward-balances patient)))
         (new-total (+ (get total-earned current-balance) amount))
         (new-current (+ (get current-balance current-balance) amount))
         (current-time (get-current-time))
         (new-streak (if (is-eq reward-type REWARD-DAILY-ADHERENCE)
                        (if (is-eq (+ (get last-reward-date current-balance) u1) current-time)
                            (+ (get streak-days current-balance) u1)
                            u1)
                        (get streak-days current-balance))))
        
        (map-set reward-balances
            patient
            {
                total-earned: new-total,
                total-redeemed: (get total-redeemed current-balance),
                current-balance: new-current,
                streak-days: new-streak,
                last-reward-date: current-time,
                milestone-level: (get milestone-level current-balance)
            }
        )
        new-current
    )
)

;; Public Functions

;; Record daily adherence
(define-public (record-adherence 
    (patient principal)
    (date uint)
    (medications-taken uint)
    (medications-scheduled uint)
    (notes (optional (string-utf8 200)))
)
    (let 
        ((recorder tx-sender)
         (adherence-pct (calculate-adherence-percentage medications-taken medications-scheduled))
         (is-perfect (is-perfect-adherence adherence-pct))
         (bonus-eligible (and is-perfect (> medications-scheduled u0))))
        
        (asserts! (is-authorized-recorder patient recorder) ERR-UNAUTHORIZED)
        (asserts! (> medications-scheduled u0) ERR-INVALID-AMOUNT)
        
        (map-set adherence-records
            { patient: patient, date: date }
            {
                medications-taken: medications-taken,
                medications-scheduled: medications-scheduled,
                adherence-percentage: adherence-pct,
                bonus-eligible: bonus-eligible,
                recorded-by: recorder,
                notes: notes
            }
        )
        
        ;; Award daily adherence reward if perfect
        (if bonus-eligible
            (begin
                (unwrap-panic (award-adherence-reward patient REWARD-DAILY-ADHERENCE DAILY-REWARD u"Perfect daily adherence"))
                (ok { recorded: true, reward-awarded: true, amount: DAILY-REWARD })
            )
            (ok { recorded: true, reward-awarded: false, amount: u0 })
        )
    )
)

;; Award adherence reward
(define-public (award-adherence-reward 
    (patient principal)
    (reward-type uint)
    (amount uint)
    (reason (string-utf8 200))
)
    (let 
        ((reward-id (var-get next-reward-id))
         (awarder tx-sender))
        
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount (var-get contract-token-reserve)) ERR-INSUFFICIENT-BALANCE)
        
        (map-set reward-history
            reward-id
            {
                recipient: patient,
                reward-type: reward-type,
                amount: amount,
                reason: reason,
                awarded-date: (get-current-time),
                awarded-by: awarder,
                claimed: false,
                claimed-date: none
            }
        )
        
        (var-set next-reward-id (+ reward-id u1))
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) u1))
        (var-set total-tokens-issued (+ (var-get total-tokens-issued) amount))
        (var-set contract-token-reserve (- (var-get contract-token-reserve) amount))
        
        (update-patient-balance patient amount reward-type)
        (ok reward-id)
    )
)

;; Record caregiver contribution
(define-public (record-caregiver-contribution 
    (patient principal)
    (caregiver principal)
    (period uint)
    (support-actions uint)
    (reminder-assists uint)
    (medication-helps uint)
    (emotional-support uint)
)
    (let 
        ((recorder tx-sender)
         (total-score (+ (+ support-actions reminder-assists) (+ medication-helps emotional-support)))
         (reward-amount (if (> (* total-score u5) CAREGIVER-SUPPORT-REWARD) CAREGIVER-SUPPORT-REWARD (* total-score u5))))
        
        (asserts! (is-authorized-recorder patient recorder) ERR-UNAUTHORIZED)
        
        (map-set caregiver-contributions
            { patient: patient, caregiver: caregiver, period: period }
            {
                support-actions: support-actions,
                reminder-assists: reminder-assists,
                medication-helps: medication-helps,
                emotional-support: emotional-support,
                total-contribution-score: total-score,
                reward-earned: reward-amount,
                period-start: period,
                period-end: (+ period u30) ;; 30-day period
            }
        )
        
        ;; Award caregiver support reward
        (if (> reward-amount u0)
            (unwrap-panic (award-adherence-reward caregiver REWARD-CAREGIVER-SUPPORT reward-amount u"Caregiver support contribution"))
            u0
        )
        
        (ok reward-amount)
    )
)

;; Check and award streak bonus
(define-public (check-streak-bonus (patient principal))
    (let 
        ((balance-info (unwrap! (map-get? reward-balances patient) ERR-PATIENT-NOT-FOUND))
         (streak-days (get streak-days balance-info))
         (bonus-amount (calculate-streak-bonus streak-days)))
        
        (if (> bonus-amount u0)
            (begin
                (unwrap-panic (award-adherence-reward patient REWARD-WEEKLY-STREAK bonus-amount u"Streak bonus achievement"))
                (ok { bonus-awarded: true, amount: bonus-amount, streak-days: streak-days })
            )
            (ok { bonus-awarded: false, amount: u0, streak-days: streak-days })
        )
    )
)

;; Create milestone
(define-public (create-milestone 
    (title (string-utf8 100))
    (description (string-utf8 300))
    (requirement-type (string-utf8 50))
    (requirement-value uint)
    (reward-multiplier uint)
    (badge-earned (string-utf8 100))
)
    (let 
        ((milestone-id (var-get next-milestone-id)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        
        (map-set milestone-definitions
            milestone-id
            {
                title: title,
                description: description,
                requirement-type: requirement-type,
                requirement-value: requirement-value,
                reward-multiplier: reward-multiplier,
                badge-earned: badge-earned,
                active: true
            }
        )
        
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

;; Claim milestone reward
(define-public (claim-milestone-reward (milestone-id uint))
    (let 
        ((patient tx-sender)
         (milestone (unwrap! (map-get? milestone-definitions milestone-id) ERR-REWARD-NOT-FOUND))
         (patient-progress (default-to { achieved: false, achieved-date: none, progress-value: u0, reward-claimed: false } 
                                      (map-get? patient-milestones { patient: patient, milestone-id: milestone-id })))
         (reward-amount (* MILESTONE-BASE-REWARD (get reward-multiplier milestone))))
        
        (asserts! (get achieved patient-progress) ERR-MILESTONE-NOT-REACHED)
        (asserts! (not (get reward-claimed patient-progress)) ERR-ALREADY-CLAIMED)
        
        (map-set patient-milestones
            { patient: patient, milestone-id: milestone-id }
            (merge patient-progress { reward-claimed: true })
        )
        
        (unwrap-panic (award-adherence-reward patient REWARD-MILESTONE-ACHIEVEMENT reward-amount u"Milestone achievement reward"))
        (ok reward-amount)
    )
)

;; Redeem tokens for rewards
(define-public (redeem-tokens (option-id uint) (token-amount uint))
    (let 
        ((patient tx-sender)
         (balance-info (unwrap! (map-get? reward-balances patient) ERR-PATIENT-NOT-FOUND))
         (option (unwrap! (map-get? redemption-options option-id) ERR-REWARD-NOT-FOUND)))
        
        (asserts! (get available option) ERR-REWARD-NOT-FOUND)
        (asserts! (>= (get current-balance balance-info) token-amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (>= token-amount (get cost option)) ERR-INVALID-AMOUNT)
        
        (map-set reward-balances
            patient
            (merge balance-info {
                total-redeemed: (+ (get total-redeemed balance-info) token-amount),
                current-balance: (- (get current-balance balance-info) token-amount)
            })
        )
        
        (ok { redeemed: true, amount: token-amount, option: (get title option) })
    )
)

;; Read-only Functions

;; Get adherence record
(define-read-only (get-adherence-record (patient principal) (date uint))
    (map-get? adherence-records { patient: patient, date: date })
)

;; Get reward balance
(define-read-only (get-reward-balance (patient principal))
    (map-get? reward-balances patient)
)

;; Get reward history
(define-read-only (get-reward-history (reward-id uint))
    (map-get? reward-history reward-id)
)

;; Get caregiver contribution
(define-read-only (get-caregiver-contribution (patient principal) (caregiver principal) (period uint))
    (map-get? caregiver-contributions { patient: patient, caregiver: caregiver, period: period })
)

;; Get milestone info
(define-read-only (get-milestone (milestone-id uint))
    (map-get? milestone-definitions milestone-id)
)

;; Get patient milestone progress
(define-read-only (get-patient-milestone (patient principal) (milestone-id uint))
    (map-get? patient-milestones { patient: patient, milestone-id: milestone-id })
)

;; Get redemption option
(define-read-only (get-redemption-option (option-id uint))
    (map-get? redemption-options option-id)
)

;; Get contract statistics
(define-read-only (get-reward-stats)
    {
        total-rewards-distributed: (var-get total-rewards-distributed),
        total-tokens-issued: (var-get total-tokens-issued),
        contract-token-reserve: (var-get contract-token-reserve),
        next-reward-id: (var-get next-reward-id),
        next-milestone-id: (var-get next-milestone-id)
    }
)

;; Calculate potential reward for adherence
(define-read-only (calculate-potential-reward (adherence-percentage uint) (consecutive-days uint))
    (let 
        ((base-reward (if (>= adherence-percentage u100) DAILY-REWARD u0))
         (streak-bonus (calculate-streak-bonus consecutive-days)))
        (+ base-reward streak-bonus)
    )
)

;; title: medication-adherence-rewards
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

