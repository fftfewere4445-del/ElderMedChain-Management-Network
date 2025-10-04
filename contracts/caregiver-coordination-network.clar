;; Caregiver Coordination Network Smart Contract
;; Coordinate family caregivers and healthcare providers for comprehensive medication management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-PATIENT-NOT-FOUND (err u301))
(define-constant ERR-CAREGIVER-NOT-FOUND (err u302))
(define-constant ERR-CARE-PLAN-NOT-FOUND (err u303))
(define-constant ERR-ALREADY-EXISTS (err u304))
(define-constant ERR-INVALID-ROLE (err u305))
(define-constant ERR-EMERGENCY-CONTACT-REQUIRED (err u306))

;; Role Types
(define-constant ROLE-PRIMARY-CAREGIVER u1)
(define-constant ROLE-FAMILY-MEMBER u2)
(define-constant ROLE-HEALTHCARE-PROVIDER u3)
(define-constant ROLE-EMERGENCY-CONTACT u4)
(define-constant ROLE-NURSE u5)

;; Emergency Levels
(define-constant EMERGENCY-LOW u1)
(define-constant EMERGENCY-MEDIUM u2)
(define-constant EMERGENCY-HIGH u3)
(define-constant EMERGENCY-CRITICAL u4)

;; Data Structures
(define-map care-network-members
    { patient: principal, member: principal }
    {
        role: uint,
        permissions: uint, ;; bit flags for different permissions
        contact-info: (string-utf8 200),
        relationship: (string-utf8 100),
        priority-level: uint,
        added-by: principal,
        added-at: uint,
        active: bool,
        emergency-contact: bool
    }
)

(define-map care-plans
    { patient: principal, plan-id: uint }
    {
        title: (string-utf8 150),
        description: (string-utf8 500),
        created-by: principal,
        created-at: uint,
        last-updated: uint,
        target-goals: (string-utf8 300),
        medication-focus: bool,
        emergency-protocols: (string-utf8 400),
        review-frequency: uint,
        active: bool
    }
)

(define-map care-updates
    uint ;; update-id
    {
        patient: principal,
        plan-id: uint,
        update-type: (string-utf8 50),
        message: (string-utf8 400),
        urgency-level: uint,
        created-by: principal,
        created-at: uint,
        acknowledged-by: (list 10 principal),
        requires-response: bool,
        resolved: bool
    }
)

(define-map emergency-alerts
    uint ;; alert-id
    {
        patient: principal,
        alert-type: (string-utf8 100),
        severity: uint,
        message: (string-utf8 500),
        location: (optional (string-utf8 200)),
        triggered-by: principal,
        triggered-at: uint,
        notified-members: (list 20 principal),
        response-received: bool,
        resolved: bool,
        resolution-notes: (optional (string-utf8 300))
    }
)

(define-map communication-log
    uint ;; message-id
    {
        patient: principal,
        sender: principal,
        recipients: (list 10 principal),
        subject: (string-utf8 150),
        message: (string-utf8 500),
        message-type: (string-utf8 50),
        priority: uint,
        sent-at: uint,
        read-by: (list 10 principal)
    }
)

;; Data Variables
(define-data-var next-plan-id uint u1)
(define-data-var next-update-id uint u1)
(define-data-var next-alert-id uint u1)
(define-data-var next-message-id uint u1)
(define-data-var total-networks uint u0)
(define-data-var total-plans uint u0)
(define-data-var total-alerts uint u0)

;; Private Functions
(define-private (is-care-network-member (patient principal) (member principal))
    (is-some (map-get? care-network-members { patient: patient, member: member }))
)

(define-private (has-permission (patient principal) (member principal) (required-permission uint))
    (match (map-get? care-network-members { patient: patient, member: member })
        member-info (> (bit-and (get permissions member-info) required-permission) u0)
        false
    )
)

(define-private (is-authorized-for-patient (patient principal) (user principal))
    (or 
        (is-eq user patient)
        (is-care-network-member patient user)
        (is-eq user CONTRACT-OWNER)
    )
)

(define-private (get-current-time)
    burn-block-height
)

(define-private (add-to-list-if-not-present (item principal) (current-list (list 10 principal)))
    (if (is-some (index-of current-list item))
        current-list
        (unwrap-panic (as-max-len? (append current-list item) u10))
    )
)

;; Public Functions

;; Add caregiver to network
(define-public (add-caregiver 
    (patient principal)
    (caregiver principal)
    (role uint)
    (permissions uint)
    (contact-info (string-utf8 200))
    (relationship (string-utf8 100))
    (priority-level uint)
    (emergency-contact bool)
)
    (let 
        ((requester tx-sender))
        (asserts! (is-authorized-for-patient patient requester) ERR-UNAUTHORIZED)
        (asserts! (<= role ROLE-NURSE) ERR-INVALID-ROLE)
        (asserts! (> role u0) ERR-INVALID-ROLE)
        (asserts! (is-none (map-get? care-network-members { patient: patient, member: caregiver })) ERR-ALREADY-EXISTS)
        
        (map-set care-network-members
            { patient: patient, member: caregiver }
            {
                role: role,
                permissions: permissions,
                contact-info: contact-info,
                relationship: relationship,
                priority-level: priority-level,
                added-by: requester,
                added-at: (get-current-time),
                active: true,
                emergency-contact: emergency-contact
            }
        )
        (var-set total-networks (+ (var-get total-networks) u1))
        (ok true)
    )
)

;; Create care plan
(define-public (create-care-plan 
    (patient principal)
    (title (string-utf8 150))
    (description (string-utf8 500))
    (target-goals (string-utf8 300))
    (medication-focus bool)
    (emergency-protocols (string-utf8 400))
    (review-frequency uint)
)
    (let 
        ((plan-id (var-get next-plan-id))
         (creator tx-sender))
        (asserts! (is-authorized-for-patient patient creator) ERR-UNAUTHORIZED)
        
        (map-set care-plans
            { patient: patient, plan-id: plan-id }
            {
                title: title,
                description: description,
                created-by: creator,
                created-at: (get-current-time),
                last-updated: (get-current-time),
                target-goals: target-goals,
                medication-focus: medication-focus,
                emergency-protocols: emergency-protocols,
                review-frequency: review-frequency,
                active: true
            }
        )
        (var-set next-plan-id (+ plan-id u1))
        (var-set total-plans (+ (var-get total-plans) u1))
        (ok plan-id)
    )
)

;; Post care update
(define-public (post-care-update 
    (patient principal)
    (plan-id uint)
    (update-type (string-utf8 50))
    (message (string-utf8 400))
    (urgency-level uint)
    (requires-response bool)
)
    (let 
        ((update-id (var-get next-update-id))
         (poster tx-sender))
        (asserts! (is-authorized-for-patient patient poster) ERR-UNAUTHORIZED)
        (asserts! (is-some (map-get? care-plans { patient: patient, plan-id: plan-id })) ERR-CARE-PLAN-NOT-FOUND)
        
        (map-set care-updates
            update-id
            {
                patient: patient,
                plan-id: plan-id,
                update-type: update-type,
                message: message,
                urgency-level: urgency-level,
                created-by: poster,
                created-at: (get-current-time),
                acknowledged-by: (list),
                requires-response: requires-response,
                resolved: false
            }
        )
        (var-set next-update-id (+ update-id u1))
        (ok update-id)
    )
)

;; Trigger emergency alert
(define-public (trigger-emergency-alert 
    (patient principal)
    (alert-type (string-utf8 100))
    (severity uint)
    (message (string-utf8 500))
    (location (optional (string-utf8 200)))
)
    (let 
        ((alert-id (var-get next-alert-id))
         (trigger-by tx-sender))
        (asserts! (is-authorized-for-patient patient trigger-by) ERR-UNAUTHORIZED)
        (asserts! (<= severity EMERGENCY-CRITICAL) ERR-INVALID-ROLE)
        (asserts! (> severity u0) ERR-INVALID-ROLE)
        
        (map-set emergency-alerts
            alert-id
            {
                patient: patient,
                alert-type: alert-type,
                severity: severity,
                message: message,
                location: location,
                triggered-by: trigger-by,
                triggered-at: (get-current-time),
                notified-members: (list),
                response-received: false,
                resolved: false,
                resolution-notes: none
            }
        )
        (var-set next-alert-id (+ alert-id u1))
        (var-set total-alerts (+ (var-get total-alerts) u1))
        (ok alert-id)
    )
)

;; Send communication message
(define-public (send-message 
    (patient principal)
    (recipients (list 10 principal))
    (subject (string-utf8 150))
    (message (string-utf8 500))
    (message-type (string-utf8 50))
    (priority uint)
)
    (let 
        ((message-id (var-get next-message-id))
         (sender tx-sender))
        (asserts! (is-authorized-for-patient patient sender) ERR-UNAUTHORIZED)
        
        (map-set communication-log
            message-id
            {
                patient: patient,
                sender: sender,
                recipients: recipients,
                subject: subject,
                message: message,
                message-type: message-type,
                priority: priority,
                sent-at: (get-current-time),
                read-by: (list)
            }
        )
        (var-set next-message-id (+ message-id u1))
        (ok message-id)
    )
)

;; Acknowledge care update
(define-public (acknowledge-update (update-id uint))
    (let 
        ((user tx-sender)
         (update (unwrap! (map-get? care-updates update-id) ERR-CARE-PLAN-NOT-FOUND)))
        (asserts! (is-authorized-for-patient (get patient update) user) ERR-UNAUTHORIZED)
        
        (map-set care-updates
            update-id
            (merge update {
                acknowledged-by: (add-to-list-if-not-present user (get acknowledged-by update))
            })
        )
        (ok true)
    )
)

;; Resolve emergency alert
(define-public (resolve-emergency-alert (alert-id uint) (resolution-notes (string-utf8 300)))
    (let 
        ((resolver tx-sender)
         (alert (unwrap! (map-get? emergency-alerts alert-id) ERR-CARE-PLAN-NOT-FOUND)))
        (asserts! (is-authorized-for-patient (get patient alert) resolver) ERR-UNAUTHORIZED)
        
        (map-set emergency-alerts
            alert-id
            (merge alert {
                resolved: true,
                resolution-notes: (some resolution-notes),
                response-received: true
            })
        )
        (ok true)
    )
)

;; Update caregiver permissions
(define-public (update-caregiver-permissions 
    (patient principal)
    (caregiver principal)
    (new-permissions uint)
)
    (let 
        ((requester tx-sender)
         (member-info (unwrap! (map-get? care-network-members { patient: patient, member: caregiver }) ERR-CAREGIVER-NOT-FOUND)))
        (asserts! (is-authorized-for-patient patient requester) ERR-UNAUTHORIZED)
        
        (map-set care-network-members
            { patient: patient, member: caregiver }
            (merge member-info { permissions: new-permissions })
        )
        (ok true)
    )
)

;; Read-only Functions

;; Get caregiver info
(define-read-only (get-caregiver-info (patient principal) (caregiver principal))
    (map-get? care-network-members { patient: patient, member: caregiver })
)

;; Get care plan
(define-read-only (get-care-plan (patient principal) (plan-id uint))
    (map-get? care-plans { patient: patient, plan-id: plan-id })
)

;; Get care update
(define-read-only (get-care-update (update-id uint))
    (map-get? care-updates update-id)
)

;; Get emergency alert
(define-read-only (get-emergency-alert (alert-id uint))
    (map-get? emergency-alerts alert-id)
)

;; Get communication message
(define-read-only (get-message (message-id uint))
    (map-get? communication-log message-id)
)

;; Get coordination statistics
(define-read-only (get-coordination-stats)
    {
        total-networks: (var-get total-networks),
        total-plans: (var-get total-plans),
        total-alerts: (var-get total-alerts),
        next-plan-id: (var-get next-plan-id),
        next-alert-id: (var-get next-alert-id),
        next-message-id: (var-get next-message-id)
    }
)

;; Check network membership
(define-read-only (check-network-membership (patient principal) (member principal))
    (is-care-network-member patient member)
)

;; Check permissions
(define-read-only (check-member-permissions (patient principal) (member principal) (permission uint))
    (has-permission patient member permission)
)

;; title: caregiver-coordination-network
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

