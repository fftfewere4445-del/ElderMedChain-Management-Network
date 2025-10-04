;; Drug Interaction Monitoring Smart Contract
;; Monitor potential drug interactions and alert healthcare providers of dangerous combinations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-DRUG-NOT-FOUND (err u201))
(define-constant ERR-INTERACTION-NOT-FOUND (err u202))
(define-constant ERR-ALREADY-EXISTS (err u203))
(define-constant ERR-INVALID-SEVERITY (err u204))
(define-constant ERR-PATIENT-NOT-FOUND (err u205))

;; Severity Levels
(define-constant SEVERITY-LOW u1)
(define-constant SEVERITY-MODERATE u2)
(define-constant SEVERITY-HIGH u3)
(define-constant SEVERITY-CRITICAL u4)

;; Data Structures
(define-map drugs
    uint ;; drug-id
    {
        name: (string-utf8 100),
        generic-name: (string-utf8 100),
        drug-class: (string-utf8 50),
        active-ingredient: (string-utf8 100),
        contraindications: (string-utf8 300),
        added-by: principal,
        created-at: uint,
        active: bool
    }
)

(define-map drug-interactions
    { drug1-id: uint, drug2-id: uint }
    {
        severity-level: uint,
        description: (string-utf8 300),
        mechanism: (string-utf8 200),
        clinical-effect: (string-utf8 200),
        management: (string-utf8 300),
        evidence-level: (string-utf8 50),
        added-by: principal,
        created-at: uint,
        verified: bool
    }
)

(define-map patient-medications
    { patient: principal, drug-id: uint }
    {
        prescribed-date: uint,
        prescriber: principal,
        dosage: (string-utf8 50),
        frequency: uint,
        active: bool,
        monitored: bool
    }
)

(define-map interaction-alerts
    uint ;; alert-id
    {
        patient: principal,
        drug1-id: uint,
        drug2-id: uint,
        severity-level: uint,
        alert-message: (string-utf8 400),
        acknowledged: bool,
        acknowledged-by: (optional principal),
        acknowledged-at: (optional uint),
        created-at: uint,
        resolved: bool
    }
)

(define-map authorized-prescribers
    principal
    {
        license-number: (string-utf8 50),
        specialty: (string-utf8 100),
        verified: bool,
        added-at: uint,
        added-by: principal
    }
)

;; Data Variables
(define-data-var next-drug-id uint u1)
(define-data-var next-alert-id uint u1)
(define-data-var total-drugs uint u0)
(define-data-var total-interactions uint u0)
(define-data-var total-alerts uint u0)

;; Private Functions
(define-private (is-authorized-prescriber (user principal))
    (or 
        (is-eq user CONTRACT-OWNER)
        (is-some (map-get? authorized-prescribers user))
    )
)

(define-private (get-current-time)
    burn-block-height
)

(define-private (create-interaction-key (drug1 uint) (drug2 uint))
    (if (< drug1 drug2)
        { drug1-id: drug1, drug2-id: drug2 }
        { drug1-id: drug2, drug2-id: drug1 }
    )
)

(define-private (generate-alert-message (drug1-name (string-utf8 100)) (drug2-name (string-utf8 100)) (severity uint) (description (string-utf8 300)))
    (if (is-eq severity SEVERITY-CRITICAL)
        u"CRITICAL ALERT: Drug interaction detected"
        (if (is-eq severity SEVERITY-HIGH)
            u"HIGH ALERT: Drug interaction detected"
            u"MODERATE ALERT: Drug interaction detected"
        )
    )
)

;; Public Functions

;; Add new drug to database
(define-public (add-drug 
    (name (string-utf8 100))
    (generic-name (string-utf8 100))
    (drug-class (string-utf8 50))
    (active-ingredient (string-utf8 100))
    (contraindications (string-utf8 300))
)
    (let 
        ((drug-id (var-get next-drug-id))
         (prescriber tx-sender))
        (asserts! (is-authorized-prescriber prescriber) ERR-UNAUTHORIZED)
        
        (map-set drugs
            drug-id
            {
                name: name,
                generic-name: generic-name,
                drug-class: drug-class,
                active-ingredient: active-ingredient,
                contraindications: contraindications,
                added-by: prescriber,
                created-at: (get-current-time),
                active: true
            }
        )
        (var-set next-drug-id (+ drug-id u1))
        (var-set total-drugs (+ (var-get total-drugs) u1))
        (ok drug-id)
    )
)

;; Add drug interaction rule
(define-public (add-drug-interaction 
    (drug1-id uint)
    (drug2-id uint)
    (severity-level uint)
    (description (string-utf8 300))
    (mechanism (string-utf8 200))
    (clinical-effect (string-utf8 200))
    (management (string-utf8 300))
    (evidence-level (string-utf8 50))
)
    (let 
        ((prescriber tx-sender)
         (interaction-key (create-interaction-key drug1-id drug2-id)))
        (asserts! (is-authorized-prescriber prescriber) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? drugs drug1-id)) ERR-DRUG-NOT-FOUND)
        (asserts! (is-some (map-get? drugs drug2-id)) ERR-DRUG-NOT-FOUND)
        (asserts! (and (<= severity-level SEVERITY-CRITICAL) (>= severity-level SEVERITY-LOW)) ERR-INVALID-SEVERITY)
        (asserts! (not (is-eq drug1-id drug2-id)) ERR-INVALID-SEVERITY)
        
        (map-set drug-interactions
            interaction-key
            {
                severity-level: severity-level,
                description: description,
                mechanism: mechanism,
                clinical-effect: clinical-effect,
                management: management,
                evidence-level: evidence-level,
                added-by: prescriber,
                created-at: (get-current-time),
                verified: false
            }
        )
        (var-set total-interactions (+ (var-get total-interactions) u1))
        (ok interaction-key)
    )
)

;; Check for drug interactions when prescribing
(define-public (check-drug-interactions (patient principal) (new-drug-id uint))
    (let 
        ((prescriber tx-sender)
         (new-drug (unwrap! (map-get? drugs new-drug-id) ERR-DRUG-NOT-FOUND)))
        (asserts! (is-authorized-prescriber prescriber) ERR-UNAUTHORIZED)
        
        ;; This is a simplified check - in practice, you'd iterate through all patient medications
        ;; For this example, we'll return success and rely on the alert system
        (ok true)
    )
)

;; Add medication to patient profile
(define-public (prescribe-medication 
    (patient principal)
    (drug-id uint)
    (dosage (string-utf8 50))
    (frequency uint)
)
    (let 
        ((prescriber tx-sender))
        (asserts! (is-authorized-prescriber prescriber) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? drugs drug-id)) ERR-DRUG-NOT-FOUND)
        
        (map-set patient-medications
            { patient: patient, drug-id: drug-id }
            {
                prescribed-date: (get-current-time),
                prescriber: prescriber,
                dosage: dosage,
                frequency: frequency,
                active: true,
                monitored: true
            }
        )
        
        ;; Auto-check for interactions (simplified)
        (unwrap! (check-drug-interactions patient drug-id) ERR-UNAUTHORIZED)
        (ok true)
    )
)

;; Create interaction alert
(define-public (create-interaction-alert 
    (patient principal)
    (drug1-id uint)
    (drug2-id uint)
)
    (let 
        ((alert-id (var-get next-alert-id))
         (interaction-key (create-interaction-key drug1-id drug2-id))
         (interaction (unwrap! (map-get? drug-interactions interaction-key) ERR-INTERACTION-NOT-FOUND))
         (drug1 (unwrap! (map-get? drugs drug1-id) ERR-DRUG-NOT-FOUND))
         (drug2 (unwrap! (map-get? drugs drug2-id) ERR-DRUG-NOT-FOUND))
         (alert-msg (generate-alert-message (get name drug1) (get name drug2) (get severity-level interaction) (get description interaction))))
        
        (map-set interaction-alerts
            alert-id
            {
                patient: patient,
                drug1-id: drug1-id,
                drug2-id: drug2-id,
                severity-level: (get severity-level interaction),
                alert-message: alert-msg,
                acknowledged: false,
                acknowledged-by: none,
                acknowledged-at: none,
                created-at: (get-current-time),
                resolved: false
            }
        )
        (var-set next-alert-id (+ alert-id u1))
        (var-set total-alerts (+ (var-get total-alerts) u1))
        (ok alert-id)
    )
)

;; Acknowledge alert
(define-public (acknowledge-alert (alert-id uint))
    (let 
        ((user tx-sender)
         (alert (unwrap! (map-get? interaction-alerts alert-id) ERR-INTERACTION-NOT-FOUND)))
        (asserts! (is-authorized-prescriber user) ERR-UNAUTHORIZED)
        
        (map-set interaction-alerts
            alert-id
            (merge alert {
                acknowledged: true,
                acknowledged-by: (some user),
                acknowledged-at: (some (get-current-time))
            })
        )
        (ok true)
    )
)

;; Authorize prescriber
(define-public (authorize-prescriber 
    (prescriber principal)
    (license-number (string-utf8 50))
    (specialty (string-utf8 100))
)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-prescribers
            prescriber
            {
                license-number: license-number,
                specialty: specialty,
                verified: true,
                added-at: (get-current-time),
                added-by: CONTRACT-OWNER
            }
        )
        (ok true)
    )
)

;; Read-only Functions

;; Get drug information
(define-read-only (get-drug (drug-id uint))
    (map-get? drugs drug-id)
)

;; Get interaction information
(define-read-only (get-interaction (drug1-id uint) (drug2-id uint))
    (map-get? drug-interactions (create-interaction-key drug1-id drug2-id))
)

;; Get patient medication
(define-read-only (get-patient-medication (patient principal) (drug-id uint))
    (map-get? patient-medications { patient: patient, drug-id: drug-id })
)

;; Get alert information
(define-read-only (get-alert (alert-id uint))
    (map-get? interaction-alerts alert-id)
)

;; Get prescriber authorization
(define-read-only (get-prescriber-info (prescriber principal))
    (map-get? authorized-prescribers prescriber)
)

;; Get contract statistics
(define-read-only (get-monitoring-stats)
    {
        total-drugs: (var-get total-drugs),
        total-interactions: (var-get total-interactions),
        total-alerts: (var-get total-alerts),
        next-drug-id: (var-get next-drug-id),
        next-alert-id: (var-get next-alert-id)
    }
)

;; Check if user is authorized prescriber
(define-read-only (check-prescriber-authorization (user principal))
    (is-authorized-prescriber user)
)

;; title: drug-interaction-monitoring
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

