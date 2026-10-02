"""Operational content added in lab version 2: customer procedures, runbooks, escalation and
technician patterns in the ticket history, sensitive test values for the data protection
exercise, the labelled customer configuration document, and the two new incidents that wait
in the queue.

Everything here is fictional and deterministic: no random draws, so adding it never changes
the historical tickets that the generator builds from ticket_templates.py. The guides depend
on specific records here; search for "EXERCISE" before changing anything.
"""

# ===========================================================================
# Customer procedures. Every customer gets an escalation-contacts procedure and a change
# procedure; Break-Fix customers also get a billing procedure. SPECIAL_PROCEDURES adds the
# hand-authored ones that the exercises rely on.
# ===========================================================================
ESCALATION_HOURS = {
    "Platinum": "P1 incidents are escalated around the clock, every day of the year.",
    "Gold": "P1 incidents are escalated around the clock; P2 incidents from 07:00 to 21:00 on weekdays.",
    "Silver": "P1 and P2 incidents are escalated from 07:00 to 20:00 on weekdays.",
    "Bronze": "Incidents are escalated during business hours only, 08:00 to 18:00 on weekdays.",
}
CHANGE_RULES = {
    "Fully Managed": ("Change and maintenance window",
                      "Standard changes run on Tuesday and Thursday from 20:00 to 23:00 local time. Emergency changes "
                      "outside the window need approval from the customer's IT manager by phone, recorded in the ticket."),
    "Co-Managed": ("Change approval with the customer's IT team",
                   "Every change is agreed with the customer's own IT team in the weekly change call and approved by the "
                   "customer's IT manager. Relecloud doesn't change systems the customer's team administers."),
    "Break-Fix": ("Change approval on quote",
                  "Changes start only after the customer has approved a written quote. Emergency work still needs "
                  "verbal approval from the office manager, recorded in the ticket."),
}
BILLING_RULE = ("Quotes and billable work",
                "Every piece of work outside the monitoring service is billable. Send a written quote and wait for "
                "written approval from the office manager before starting. Never take or record card details in a "
                "ticket; payments go through Relecloud billing.")

# EXERCISE: these procedures are cited by the expected results in the guides.
SPECIAL_PROCEDURES = [
    {"customer": "CUST-001", "type": "Change approval", "title": "Regulated systems change control",
     "applies_to": "Laboratory and manufacturing systems",
     "details": "Changes to laboratory and manufacturing systems need a change ticket approved by the customer's quality "
                "team before any work starts. Record the quality team's approval reference in the ticket."},
    {"customer": "CUST-002", "type": "Maintenance window", "title": "Remote workers and weekend maintenance",
     "applies_to": "Secure Gateway, Remote Access",
     "details": "Property managers work from home and depend on Remote Access. Network maintenance runs on Saturday "
                "mornings; tell the operations contact before any change that can disconnect remote staff."},
    {"customer": "CUST-007", "type": "Business hours", "title": "Branch and mortgage team connectivity",
     "applies_to": "Remote Access, Secure Gateway",
     "details": "Remote Access problems that affect the mortgage team or branch managers on client visits are handled as "
                "P2. Tell the bank's IT manager about any Secure Gateway firmware change one week ahead."},
    {"customer": "CUST-008", "type": "Business hours", "title": "Payroll calendar",
     "applies_to": "Payroll application",
     "details": "Payroll is submitted every Thursday. Treat any payroll application problem from Tuesday to Thursday as P2."},
    {"customer": "CUST-013", "type": "Business hours", "title": "Claims intake hours",
     "applies_to": "Document management application",
     "details": "The document management application is business-critical during claims intake hours, 08:00 to 18:00 "
                "local time. Treat an outage in those hours as P2 or higher, and never offer service credits without "
                "the account manager's approval."},
    {"customer": "CUST-014", "type": "Data handling", "title": "Clinical data handling",
     "applies_to": "All tickets",
     "details": "Never record patient information in tickets or notes. This customer's records are held by the Relecloud "
                "Regulated Accounts team, and changes to them follow that team's process."},
    {"customer": "CUST-015", "type": "Billing and quotes", "title": "Storage billing",
     "applies_to": "Backup vault",
     "details": "Vault size increases are billed monthly and approved by the finance director. Card details are never "
                "taken or kept in tickets."},
    {"customer": "CUST-019", "type": "Change approval", "title": "Backup retention and vault size changes",
     "applies_to": "Relecloud Backup Agent, cloud vault",
     "details": "Retention changes and vault size increases need written approval from the customer's IT manager. The "
                "account manager, Owen Fletcher, quotes vault increases. Large archive imports must be announced to "
                "Relecloud a week ahead so the vault can be sized first."},
    {"customer": "CUST-020", "type": "Business hours", "title": "Dispatch hours",
     "applies_to": "Routing application",
     "details": "Dispatchers need the routing application from 06:00 local time. Treat a routing application outage that "
                "stops dispatchers as P2, and phone the operations contact straight away."},
]

# ===========================================================================
# Runbooks: operational procedures, indexed alongside the knowledge base.
# ===========================================================================
RUNBOOKS = [
    {"code": "RB-001", "title": "Backup failure triage", "category": "Backup and Recovery", "product": "Relecloud Backup Agent",
     "trigger": "A scheduled backup job fails, or the console shows that no new recovery point was created.",
     "steps": "1. Read the error code in the backup console. 2. RBA-1043 after patching: follow KB0007. RBA-2201 (vault "
              "quota): follow RB-002 and KB0023. RBA-3105 after an update: follow KB0028. Status Unknown: follow KB0039. "
              "3. Set the response target from the customer's SLA tier (KB0012 or KB0013). 4. Record every failed night in "
              "the ticket.",
     "escalation": "Escalate to the L3 backup engineer after two failed nights or when a restore is needed.",
     "related": "KB0007, KB0023, KB0028, KB0039, KB0012, KB0013"},
    {"code": "RB-002", "title": "Vault capacity and retention changes", "category": "Backup and Recovery", "product": "Relecloud Backup Agent",
     "trigger": "RBA-2201 vault quota exceeded, or the vault is above 90 percent of its contracted size.",
     "steps": "1. Check vault usage and the largest recent growth in the backup console. 2. Compare the retention policy "
              "with the contract. 3. Ask the account manager to quote a vault size increase. 4. Reduce retention, at most "
              "to 30 days, only with the customer's written approval, following the customer's own procedure. 5. Record "
              "the approval reference in the ticket.",
     "escalation": "Escalate to the account manager for the quote.",
     "related": "KB0023"},
    {"code": "RB-003", "title": "Remote Access hourly disconnects", "category": "Network and VPN", "product": "Relecloud Remote Access",
     "trigger": "Remote Access users are disconnected about every hour.",
     "steps": "1. Confirm the Remote Access client version and the Secure Gateway firmware from the customer profile. "
              "2. Client 3.x: follow KB0031. Client 4.x on firmware 10.1: follow KB0058. 3. Collect the client log and look "
              "for RRA-4012. 4. Don't reinstall the client for 4.x clients.",
     "escalation": "Escalate to the L3 network engineer; while the L3 engineer is unavailable, the L2 network engineer "
                   "leads and the vendor is engaged.",
     "related": "KB0031, KB0058"},
    {"code": "RB-004", "title": "Site-to-site tunnel down", "category": "Network and VPN", "product": "Relecloud Secure Gateway",
     "trigger": "A branch or warehouse can't reach head office systems while internet access works.",
     "steps": "1. Check the tunnel status on both gateways. 2. Ask whether the site's internet provider or public IP "
              "changed. 3. Follow KB0042 to update the peer address.",
     "escalation": "Escalate to the customer's internet provider through the customer's contact.",
     "related": "KB0042"},
    {"code": "RB-005", "title": "Certificate expired on a line-of-business application", "category": "Line-of-Business App",
     "product": "Line-of-business application",
     "trigger": "Users see a certificate expired or not valid warning when they open a line-of-business application.",
     "steps": "1. Identify the server and site binding that serves the application. 2. Check which server the certificate "
              "was last renewed on. 3. Follow KB0133 to bind the renewed certificate. 4. Set the priority from the "
              "business impact: several users or a time-critical process blocked is P2.",
     "escalation": "Escalate to the application vendor when the binding is managed by the vendor.",
     "related": "KB0133"},
    {"code": "RB-006", "title": "Suspicious sign-in response", "category": "Security", "product": "Microsoft 365",
     "trigger": "Monitoring raises a sign-in from an unfamiliar location or device.",
     "steps": "1. Follow KB0141. 2. Reach the user by phone, not e-mail. 3. Revoke sessions and reset credentials if the "
              "user didn't sign in.",
     "escalation": "A confirmed compromise is declared a major incident by the duty manager.",
     "related": "KB0141"},
    {"code": "RB-007", "title": "Ransomware indicator", "category": "Security", "product": "Relecloud Endpoint Agent",
     "trigger": "The Endpoint Agent reports a ransomware indicator.",
     "steps": "1. Isolate the device with KB0143. 2. Don't reboot or wipe it. 3. Preserve the alert details in the ticket.",
     "escalation": "Always a major incident, declared by the duty manager.",
     "related": "KB0143"},
    {"code": "RB-008", "title": "Repeated account lockouts", "category": "Identity and Access", "product": "Microsoft 365",
     "trigger": "A user is locked out several times a day.",
     "steps": "1. Follow KB0099 to find the source device. 2. Clear stored credentials on that device.",
     "escalation": "Escalate to the security team if the source is unknown.",
     "related": "KB0099"},
    {"code": "RB-009", "title": "Major incident (P1) handling", "category": None, "product": "Not product specific",
     "trigger": "A whole site or business function can't work, or a security incident is confirmed.",
     "steps": "1. A person, the duty manager, declares the P1. Agents and automation never set P1. 2. Open the bridge. "
              "3. Notify the customer's escalation contacts from their procedure. 4. Update the customer every 30 minutes.",
     "escalation": "Duty manager, then the account manager.",
     "related": "KB0141, KB0143"},
    {"code": "RB-010", "title": "Printer offline after a network change", "category": "Printing", "product": "Printer or scanner",
     "trigger": "A printer shows offline for everyone after network work.",
     "steps": "1. Follow KB0111. 2. Reserve the printer's address on the gateway.",
     "escalation": "Escalate to the network team if the address can't be reserved.",
     "related": "KB0111"},
    {"code": "RB-011", "title": "Endpoint performance after an agent update", "category": "Endpoint", "product": "Relecloud Endpoint Agent",
     "trigger": "Several laptops are slow after an Endpoint Agent update.",
     "steps": "1. Check the agent version. 2. Version 7.4.0: follow KB0067. 3. Confirm the scan schedule.",
     "escalation": "Escalate to the L2 endpoint engineer.",
     "related": "KB0067"},
    {"code": "RB-012", "title": "New starter and leaver requests", "category": "Identity and Access", "product": "Microsoft 365",
     "trigger": "A customer asks for an account for a new starter, or to disable a leaver.",
     "steps": "1. New starter: follow KB0095. 2. Leaver: follow KB0097 and disable within 24 hours.",
     "escalation": "None; these are standard requests.",
     "related": "KB0095, KB0097"},
]

# ===========================================================================
# Patterns applied to the historical tickets after they are generated.
# EXERCISE: Exercise 2 Task 3 and Exercise 4 Task 3 cite the technician pattern for vault
# quota tickets (KB0023, always Priya Raman); Exercise 7 cites the certificate pattern
# (KB0133, always Daniel Cho).
# ===========================================================================
TECHNICIAN_BY_ARTICLE = {
    "KB0023": "TECH-01",
    "KB0133": "TECH-06",
    "KB0131": "TECH-06",
    "KB0031": "TECH-08",
    "KB0058": "TECH-08",
    "KB0042": "TECH-08",
    "KB0141": "TECH-07",
    "KB0143": "TECH-07",
}

# (article or None for any, customer or None for any, priority or None for any) -> escalation.
# The first matching rule wins. EXERCISE: Exercise 2 Task 2 asks for Woodgrove Bank's
# previously escalated tickets.
ESCALATION_RULES = [
    {"priority": 1, "level": "Major Incident",
     "reason": "Declared a major incident by the duty manager; the major incident process was followed."},
    {"customer": "CUST-007", "category": "Network and VPN", "level": "L3 Specialist",
     "reason": "Branch connectivity problem escalated to the L3 network engineer under the bank's procedure."},
    {"article": "KB0042", "level": "Vendor",
     "reason": "Raised with the customer's internet provider to confirm the new public IP address."},
    {"article": "KB0023", "level": "Account Manager",
     "reason": "Vault size increase quoted by the account manager."},
    {"article": "KB0133", "priority": 2, "level": "Vendor",
     "reason": "Application vendor engaged to confirm the certificate binding."},
]

# ===========================================================================
# Sensitive test values for Exercise 6 Task 2. Payment card numbers are the card networks'
# published test numbers; they pass the Luhn check, so the Credit Card Number sensitive
# information type detects them, but they can't be charged.
# EXERCISE: TCK-10486 is the ticket the guide uses.
# ===========================================================================
SENSITIVE_NOTES = [
    {"ticket": "TCK-10486", "internal": True, "author": "Owen Fletcher", "after_bh": 6.0,
     "body": "Finance director approved the vault increase by phone and read out the company card for the monthly "
             "charge: Mastercard 5555 5555 5555 4444, expiry 09/29. Card details must not be kept in tickets; passed to "
             "billing, remove this note once billing confirms."},
    {"ticket": "TCK-10472", "internal": True, "author": "Lucas Moreau", "after_bh": 3.0,
     "body": "Office manager approved the quote and paid the deposit by phone with Visa card 4111 1111 1111 1111, expiry "
             "12/27. Card details must not be kept in tickets; remove after billing confirms."},
    {"history_customer": "CUST-005", "internal": True, "author": "Elena Petrova",
     "body": "Customer paid the call-out fee by card over the phone: Visa 4012 8888 8888 1881, expiry 03/28. Card "
             "details passed to billing."},
    {"history_customer": "CUST-012", "internal": True, "author": "Hannah Becker",
     "body": "Store manager paid for the parts by card over the phone: Mastercard 5105 1051 0510 5100, expiry 06/28. "
             "Card details passed to billing."},
]

# ===========================================================================
# The labelled customer configuration document (Exercise 6 Task 2). It is attached to the
# customer's account as a Dataverse note, and provisioning stamps the tenant's sensitivity
# label on it when the label ID is known. Addresses are documentation ranges (RFC 5737).
# ===========================================================================
CONFIG_DOCUMENT = {
    "customer": "CUST-007",
    "filename": "Woodgrove-Bank-Secure-Gateway-configuration.docx",
    "subject": "Secure Gateway configuration (Confidential)",
    "title": "Woodgrove Bank: Secure Gateway configuration",
    "paragraphs": [
        "Woodgrove Bank: Secure Gateway configuration",
        "Classification: Confidential. Customer configuration, for Relecloud network engineers only.",
        "Gateways: six Relecloud Secure Gateway appliances on firmware 10.1.4, one per branch and one at head office.",
        "Head office public address: 203.0.113.10. Branch addresses: 203.0.113.21 to 203.0.113.25.",
        "Backup internet link at head office: 198.51.100.40.",
        "Remote Access profile WGB-STAFF: IKE phase 1 lifetime 28800 seconds (changed under KB0058), IKE phase 2 "
        "lifetime 3600 seconds, split tunnelling off.",
        "Administrative access: only from the Relecloud network operations range 192.0.2.0/24, with named "
        "administrator accounts. Break-glass access is held by the bank's IT manager.",
        "Pre-shared keys and certificates are stored in the Relecloud vault and never in this document.",
    ],
}

# ===========================================================================
# A seeded open ticket with too little information (Exercise 2 Task 3). Added to the open
# queue by the generator; it is indexed like every other seeded ticket.
# ===========================================================================
INCOMPLETE_TICKET = {
    "number": "TCK-10513", "customer": "CUST-016", "contact": 2,
    "title": "It stopped working again",
    "description": "It stopped working again this morning, same as last time. Please fix it urgently, people are waiting.",
    "category": None, "priority": None, "status": "New", "technician": None,
    "product": None, "affected": None, "channel": "Email", "elapsed_bh": 0.25, "kb": None, "notes": [],
}

# ===========================================================================
# New incidents. Provisioning loads these AFTER it exports the search content, so they are
# never in the search index: the agent has never seen them. EXERCISE: TCK-10514 is the
# incident for Exercise 2 Tasks 1 and 3 and Exercise 4 Task 3; TCK-10515 is the
# end-to-end scenario in Exercise 7.
# ===========================================================================
NEW_INCIDENTS = [
    {"number": "TCK-10514", "customer": "CUST-019", "contact": 0,
     "title": "Nightly protection job stopped creating recovery points",
     "description": "Since Saturday night the nightly protection job for our project archive server has stopped creating "
                    "new recovery points. The console says our cloud storage allowance has been used up. We copied the "
                    "2019 to 2024 drawing archive onto that server last week.",
     "channel": "Email", "elapsed_bh": 0.2},
    {"number": "TCK-10515", "customer": "CUST-020", "contact": 1,
     "title": "Dispatchers can't load routes: certificate warning",
     "description": "Since the start of the morning shift, five of our dispatchers at the north depot get a warning that "
                    "the routing application's security certificate has expired, and they can't load today's delivery "
                    "routes. Vans are waiting to leave. The south depot is working normally.",
     "channel": "Phone", "elapsed_bh": 0.1},
]
