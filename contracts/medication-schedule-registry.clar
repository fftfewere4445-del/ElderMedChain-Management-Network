;; Medication Schedule Registry Smart Contract
;; Manages complex medication schedules for elderly patients with automated reminder systems

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PATIENT-NOT-FOUND (err u101))
(define-constant ERR-SCHEDULE-NOT-FOUND (err u102))
(define-constant ERR-INVALID-TIME (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))
(define-constant ERR-INVALID-DOSAGE (err u105))

;; Data Structures
(define-map patients
    principal
    {
        name: (string-utf8 100),
        age: uint,
        emergency-contact: principal,
        created-at: uint,
        active: bool
    }
)

(define-map medication-schedules
    { patient: principal, medication-id: uint }
    {
        medication-name: (string-utf8 100),
        dosage: (string-utf8 50),
        frequency: uint, ;; times per day
        start-date: uint,
        end-date: uint,
        instructions: (string-utf8 200),
        prescriber: principal,
        active: bool,
        reminder-enabled: bool
    }
)

(define-map medication-doses
    { patient: principal, medication-id: uint, dose-time: uint }
    {
        taken: bool,
        taken-at: (optional uint),
        notes: (optional (string-utf8 100))
    }
)

(define-map authorized-caregivers
    { patient: principal, caregiver: principal }
    {
        permission-level: uint, ;; 1: view, 2: update, 3: full
        granted-at: uint,
        granted-by: principal
    }
)

;; Data Variables
(define-data-var next-medication-id uint u1)
(define-data-var total-patients uint u0)
(define-data-var total-schedules uint u0)

;; Private Functions
(define-private (is-authorized-user (patient principal) (user principal))
    (or 
        (is-eq user patient)
        (is-some (map-get? authorized-caregivers { patient: patient, caregiver: user }))
        (is-eq user CONTRACT-OWNER)
    )
)

(define-private (get-current-time)
    burn-block-height ;; Using burn block height as time approximation
)

(define-private (calculate-next-dose-time (start-time uint) (frequency uint))
    (+ start-time (/ u144 frequency)) ;; Assuming 144 blocks per day
)

;; Public Functions

;; Register a new patient
(define-public (register-patient (name (string-utf8 100)) (age uint) (emergency-contact principal))
    (let 
        ((patient tx-sender))
        (asserts! (is-none (map-get? patients patient)) ERR-ALREADY-EXISTS)
        (map-set patients
            patient
            {
                name: name,
                age: age,
                emergency-contact: emergency-contact,
                created-at: (get-current-time),
                active: true
            }
        )
        (var-set total-patients (+ (var-get total-patients) u1))
        (ok patient)
    )
)

;; Add medication schedule
(define-public (add-medication-schedule 
    (patient principal)
    (medication-name (string-utf8 100))
    (dosage (string-utf8 50))
    (frequency uint)
    (start-date uint)
    (end-date uint)
    (instructions (string-utf8 200))
    (reminder-enabled bool)
)
    (let 
        ((medication-id (var-get next-medication-id))
         (prescriber tx-sender))
        (asserts! (is-authorized-user patient prescriber) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? patients patient)) ERR-PATIENT-NOT-FOUND)
        (asserts! (> frequency u0) ERR-INVALID-DOSAGE)
        (asserts! (< start-date end-date) ERR-INVALID-TIME)
        
        (map-set medication-schedules
            { patient: patient, medication-id: medication-id }
            {
                medication-name: medication-name,
                dosage: dosage,
                frequency: frequency,
                start-date: start-date,
                end-date: end-date,
                instructions: instructions,
                prescriber: prescriber,
                active: true,
                reminder-enabled: reminder-enabled
            }
        )
        (var-set next-medication-id (+ medication-id u1))
        (var-set total-schedules (+ (var-get total-schedules) u1))
        (ok medication-id)
    )
)

;; Record dose taken
(define-public (record-dose-taken 
    (patient principal)
    (medication-id uint)
    (dose-time uint)
    (notes (optional (string-utf8 100)))
)
    (let 
        ((user tx-sender))
        (asserts! (is-authorized-user patient user) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? medication-schedules { patient: patient, medication-id: medication-id })) ERR-SCHEDULE-NOT-FOUND)
        
        (map-set medication-doses
            { patient: patient, medication-id: medication-id, dose-time: dose-time }
            {
                taken: true,
                taken-at: (some (get-current-time)),
                notes: notes
            }
        )
        (ok true)
    )
)

;; Grant caregiver access
(define-public (grant-caregiver-access 
    (caregiver principal)
    (permission-level uint)
)
    (let 
        ((patient tx-sender))
        (asserts! (is-some (map-get? patients patient)) ERR-PATIENT-NOT-FOUND)
        (asserts! (<= permission-level u3) ERR-UNAUTHORIZED)
        (asserts! (> permission-level u0) ERR-UNAUTHORIZED)
        
        (map-set authorized-caregivers
            { patient: patient, caregiver: caregiver }
            {
                permission-level: permission-level,
                granted-at: (get-current-time),
                granted-by: patient
            }
        )
        (ok true)
    )
)

;; Update medication schedule
(define-public (update-medication-schedule 
    (patient principal)
    (medication-id uint)
    (new-frequency uint)
    (new-instructions (string-utf8 200))
    (new-reminder-enabled bool)
)
    (let 
        ((user tx-sender)
         (schedule (unwrap! (map-get? medication-schedules { patient: patient, medication-id: medication-id }) ERR-SCHEDULE-NOT-FOUND)))
        (asserts! (is-authorized-user patient user) ERR-UNAUTHORIZED)
        (asserts! (> new-frequency u0) ERR-INVALID-DOSAGE)
        
        (map-set medication-schedules
            { patient: patient, medication-id: medication-id }
            (merge schedule {
                frequency: new-frequency,
                instructions: new-instructions,
                reminder-enabled: new-reminder-enabled
            })
        )
        (ok true)
    )
)

;; Deactivate medication schedule
(define-public (deactivate-schedule 
    (patient principal)
    (medication-id uint)
)
    (let 
        ((user tx-sender)
         (schedule (unwrap! (map-get? medication-schedules { patient: patient, medication-id: medication-id }) ERR-SCHEDULE-NOT-FOUND)))
        (asserts! (is-authorized-user patient user) ERR-UNAUTHORIZED)
        
        (map-set medication-schedules
            { patient: patient, medication-id: medication-id }
            (merge schedule { active: false })
        )
        (ok true)
    )
)

;; Read-only Functions

;; Get patient info
(define-read-only (get-patient (patient principal))
    (map-get? patients patient)
)

;; Get medication schedule
(define-read-only (get-medication-schedule (patient principal) (medication-id uint))
    (map-get? medication-schedules { patient: patient, medication-id: medication-id })
)

;; Get dose record
(define-read-only (get-dose-record (patient principal) (medication-id uint) (dose-time uint))
    (map-get? medication-doses { patient: patient, medication-id: medication-id, dose-time: dose-time })
)

;; Get caregiver permissions
(define-read-only (get-caregiver-permissions (patient principal) (caregiver principal))
    (map-get? authorized-caregivers { patient: patient, caregiver: caregiver })
)

;; Get total statistics
(define-read-only (get-contract-stats)
    {
        total-patients: (var-get total-patients),
        total-schedules: (var-get total-schedules),
        next-medication-id: (var-get next-medication-id)
    }
)

;; Check if user is authorized
(define-read-only (check-authorization (patient principal) (user principal))
    (is-authorized-user patient user)
)

;; title: medication-schedule-registry
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

