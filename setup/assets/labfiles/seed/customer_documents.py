"""Customer documents (spk_customerdocument), added in lab version 3: 36 plain-text documents.

  CDOC-001 to CDOC-024  Support policy, one per customer, in customer code order
  CDOC-025 to CDOC-030  Escalation procedure for the six customers with special paths
  CDOC-031 to CDOC-036  Configuration notes

Every fact comes from the same data as the rest of the seed (customer fields, contacts,
procedures, SLA targets, escalation hours and change rules), so a document never contradicts
a record. Documents never contain contact email addresses or phone numbers (those columns
are protected by column security), secrets, or real addresses: the only network addresses
are documentation ranges, and device names are invented. Woodgrove Bank's configuration
summary points to its Confidential configuration file without repeating its content.
Bodies are 1,500 to 4,000 characters of plain text with short headings.
"""
from __future__ import annotations

from catalog import (CUSTOMERS, PRIORITY_LABELS, PRIORITY_RULES, SLA_RESOLUTION_HOURS,
                     SLA_RESPONSE_HOURS)
from operations import BILLING_RULE, CHANGE_RULES, ESCALATION_HOURS, SPECIAL_PROCEDURES

# ===========================================================================
# Support policies
# ===========================================================================
COVERAGE = {
    "Fully Managed": (
        "Under the Fully Managed contract Relecloud runs these services day to day, including monitoring, patching, "
        "standard changes in the agreed maintenance window, and new device builds from the approved hardware list. "
        "Standard changes and device builds are included in the monthly fee."),
    "Co-Managed": (
        "Under the Co-Managed contract Relecloud runs these services together with the customer's own IT team, which "
        "keeps responsibility for the systems it administers. Changes are agreed in the weekly change call. "
        "Relecloud enrolls and supports the devices the customer's team builds."),
    "Break-Fix": (
        "Under the Break-Fix contract the monthly fee covers monitoring and the first diagnosis of a reported fault. "
        "Repairs, changes, upgrades, new devices, installations and parts are billable and start only after a "
        "written quote is approved."),
}
EXCLUSIONS = {
    "Fully Managed": (
        "Third-party applications beyond first-line support, hardware purchases, and projects such as office moves "
        "or new sites, which are quoted separately."),
    "Co-Managed": (
        "Systems the customer's IT team administers, the user devices and software that team supports, and "
        "projects, which are quoted separately."),
    "Break-Fix": (
        "Any work that is not covered by a quote approved in writing."),
}
EXTRA_EXCLUSIONS = {
    "CUST-003": "Desktop support, laptops and Microsoft 365 users, which Northwind's own IT team handles.",
    "CUST-004": "Shop floor PCs, the local switches and user support, which Adventure Works' IT team handles.",
    "CUST-005": "Card terminals, which the payment provider manages.",
    "CUST-006": "Changes to the customs submission application and its templates, which only its vendor makes.",
    "CUST-008": "The payroll application server and its certificate, which Lucerne's IT team administers.",
    "CUST-011": "User accounts and PCs, which Coho's own IT contact manages.",
    "CUST-014": "Clinical systems, which the customer's software vendor hosts and supports.",
    "CUST-015": "Analysts' laptops and software, which Trey's IT team supports.",
    "CUST-018": "Student support, which the college IT team provides.",
    "CUST-019": "CAD workstations and engineers' laptops, which A. Datum's IT team supports.",
    "CUST-021": "Airport systems and their networks, which Blue Yonder's in-house IT team owns.",
    "CUST-022": "The control room network, which the utility's own engineers manage.",
    "CUST-024": "Build servers, which Proseware's engineers manage; they are excluded from monitoring and backup.",
}


def _hours(value: float) -> str:
    if value < 1:
        return f"{int(round(value * 60))} minutes"
    whole = int(value) if float(value).is_integer() else value
    return f"{whole} business hour" + ("" if whole == 1 else "s")


def _person(contact: dict) -> str:
    return f"{contact['first']} {contact['last']}"


def support_policy(customer: dict, contacts: list[dict], procedures: list[dict]) -> str:
    tier, contract = customer["tier"], customer["contract"]
    targets = "\n".join(
        f"{PRIORITY_LABELS[p]}: first response within {_hours(SLA_RESPONSE_HOURS[tier][p])}, "
        f"resolution within {_hours(SLA_RESOLUTION_HOURS[tier][p])}." for p in (1, 2, 3, 4))
    exclusions = EXCLUSIONS[contract]
    if customer["code"] in EXTRA_EXCLUSIONS:
        exclusions += " " + EXTRA_EXCLUSIONS[customer["code"]]
    approvals = CHANGE_RULES[contract][1]
    if contract == "Break-Fix":
        approvals += " " + BILLING_RULE[1]
    for special in SPECIAL_PROCEDURES:
        if special["customer"] == customer["code"] and special["type"] == "Change approval":
            approvals += " " + special["details"]
    escalation_code = next(p["code"] for p in procedures if p["type"] == "Escalation contacts")
    agreed = "\n".join(f"{p['code']}: {p['title']} ({p['type']})" for p in procedures)
    return (
        f"Support policy for {customer['name']} ({customer['code']})\n"
        f"{customer['name']} receives the {contract} service under the {tier} SLA tier. Account manager: "
        f"{customer['account_manager']}. This policy summarizes what Relecloud Managed Services provides and how to "
        f"get help. Where an agreed procedure listed at the end is more specific, the procedure applies.\n\n"
        f"Support hours\n"
        f"The Relecloud Service Desk works Monday to Friday, 08:00 to 18:00 UTC. SLA clocks run only in these "
        f"business hours, on the Relecloud Standard Business Hours calendar, which has no public holidays configured "
        f"for the current period. {ESCALATION_HOURS[tier]}\n\n"
        f"Service targets for the {tier} tier (business hours)\n"
        f"{targets}\n"
        f"{PRIORITY_RULES.replace('Relecloud priority rules:', 'Priority follows the Relecloud priority rules:')}\n\n"
        f"What the contract covers\n"
        f"Services in scope: {customer['services']}\n"
        f"{COVERAGE[contract]}\n\n"
        f"What the contract does not cover\n"
        f"{exclusions}\n\n"
        f"How to raise a ticket\n"
        f"Use the support portal or email the service desk for anything that is not urgent, and also phone the "
        f"service desk for P1 and P2 problems. Monitoring alerts open tickets automatically. Include the person and "
        f"device affected, what happened and when, the exact error message and how many people are affected; the "
        f"service desk asks for anything missing before it sets a priority.\n\n"
        f"How to escalate\n"
        f"For P1 and P2 incidents Relecloud calls {_person(contacts[0])} ({contacts[0]['job']}) first, then "
        f"{_person(contacts[2])} ({contacts[2]['job']}), as agreed in {escalation_code}. Inside Relecloud a ticket "
        f"is escalated to an L3 specialist, to the product vendor or to the account manager, and a P1 can become a "
        f"major incident, which only the duty manager declares (runbook RB-009). To escalate a ticket yourself, ask "
        f"the service desk or contact {customer['account_manager']}.\n\n"
        f"Approvals\n"
        f"{approvals}\n\n"
        f"Agreed procedures\n"
        f"{agreed}"
    )


# ===========================================================================
# Escalation procedures: six customers with special escalation paths
# ===========================================================================
ESCALATION_DOCUMENTS = [
    {"customer": "CUST-007", "version": "2.4", "reviewed_days_ago": 26, "title": "Escalation procedure: Woodgrove Bank",
     "body": (
        "Escalation procedure for Woodgrove Bank (CUST-007)\n"
        "Applies to every Woodgrove Bank incident. Read it with the support policy ({policy}) and procedures "
        "CUST-007-PR1 to CUST-007-PR3.\n\n"
        "Who Relecloud calls\n"
        "P1 and P2 incidents: phone {it} (IT Manager) first, then {sponsor} (Finance Director, executive sponsor). "
        "{ops} (Office Manager) is the contact for branch facilities, printers and access to the branches. Account "
        "manager: {am}.\n\n"
        "Branch and mortgage team connectivity\n"
        "Remote Access problems that affect the mortgage team or branch managers on client visits are handled as P2 "
        "(CUST-007-PR3). Network and Remote Access incidents are escalated to the L3 network engineer. While the L3 "
        "network engineer is unavailable, the L2 network engineer leads and the gateway vendor is engaged (runbook "
        "RB-003). Several tickets about the same symptom are linked to one change record.\n\n"
        "Gateway and firmware changes\n"
        "Tell the bank's IT manager about any Secure Gateway firmware change one week ahead. Standard changes run on "
        "Tuesday and Thursday from 20:00 to 23:00 local time (CUST-007-PR2); emergency changes outside the window "
        "need the IT manager's approval by phone, recorded in the ticket.\n\n"
        "Major incidents\n"
        "Platinum tier: P1 incidents are escalated around the clock, every day of the year. Only the duty manager "
        "declares a major incident (RB-009). The IT manager is called within 15 minutes of the declaration and "
        "updated every 30 minutes until the incident is resolved.\n\n"
        "Confidential configuration\n"
        "The Secure Gateway configuration document attached to the Woodgrove Bank account is Confidential. Never "
        "paste its contents into tickets, notes or customer emails; refer to it by its name.\n\n"
        "Account matters\n"
        "Service credits, contract questions and complaints go to {am}, never to the engineer on the ticket.")},
    {"customer": "CUST-013", "version": "3.1", "reviewed_days_ago": 41, "title": "Escalation procedure: Humongous Insurance",
     "body": (
        "Escalation procedure for Humongous Insurance (CUST-013)\n"
        "Applies to every Humongous Insurance incident. Read it with the support policy ({policy}) and procedures "
        "CUST-013-PR1 to CUST-013-PR3.\n\n"
        "Who Relecloud calls\n"
        "P1 and P2 incidents: phone {it} (IT Manager) first, then {sponsor} (Finance Director, executive sponsor). "
        "{ops} (Office Manager) coordinates the claims center floor. Account manager: {am}.\n\n"
        "Claims intake hours\n"
        "The claims document management application is business-critical during claims intake hours, 08:00 to 18:00 "
        "local time. An outage in those hours is P2 or higher (CUST-013-PR3); an outage that stops the whole claims "
        "center is P1 and the duty manager decides whether to declare a major incident (RB-009).\n\n"
        "Application faults\n"
        "Relecloud provides application support for the claims application. Certificate warnings follow runbook RB-005 "
        "and KB0133: identify the server and site binding, check where the certificate was last renewed, and bind the "
        "renewed certificate. When the binding is managed by the application vendor, escalate to the vendor and "
        "record the vendor case number in the ticket.\n\n"
        "Customer communication\n"
        "Customer updates go to the IT manager at least every two hours while a P2 is open. Updates describe the "
        "impact, the cause once it is confirmed and the next step. They never mention billing, invoices or who made "
        "a mistake.\n\n"
        "Account matters\n"
        "Service credits are never offered or promised in a ticket or an update. Only {am}, the account manager, "
        "agrees service credits, and only after finance confirms.")},
    {"customer": "CUST-001", "version": "2.2", "reviewed_days_ago": 58, "title": "Escalation procedure: Contoso Pharmaceuticals",
     "body": (
        "Escalation procedure for Contoso Pharmaceuticals (CUST-001)\n"
        "Applies to every Contoso Pharmaceuticals incident. Read it with the support policy ({policy}) and procedures "
        "CUST-001-PR1 to CUST-001-PR3.\n\n"
        "Who Relecloud calls\n"
        "P1 and P2 incidents: phone {it} (IT Manager) first, then {sponsor} (Finance Director, executive sponsor). "
        "{ops} (Office Manager) is the contact for the head office and the distribution site. Account manager: {am}.\n\n"
        "Laboratory and manufacturing systems\n"
        "A network or system outage that halts work in the laboratory building is P1. Changes to laboratory and "
        "manufacturing systems, including emergency fixes, need a change ticket approved by the customer's quality "
        "team before any work starts; record the quality team's approval reference in the ticket (CUST-001-PR3). "
        "If the quality team cannot be reached during a P1, the IT manager may approve an emergency change by phone "
        "and the quality team reviews it the next business day.\n\n"
        "Major incidents\n"
        "Platinum tier: P1 incidents are escalated around the clock, every day of the year. Only the duty manager "
        "declares a major incident (RB-009). The IT manager is called within 15 minutes of the declaration and "
        "updated every 30 minutes.\n\n"
        "Vendors\n"
        "Laboratory instrument vendors are engaged by the customer. Relecloud engages its own product vendors for "
        "Relecloud products and records the vendor case number in the ticket.\n\n"
        "Communication during incidents\n"
        "P1 updates go to the IT manager by phone, P2 updates by email at least every two hours. Copy the quality "
        "team on any update about laboratory or manufacturing systems. After a P1, send the IT manager a short "
        "incident report within three business days: what happened, the impact, the fix and what prevents a repeat.\n\n"
        "Account matters\n"
        "Contract and billing questions go to {am}.")},
    {"customer": "CUST-021", "version": "1.6", "reviewed_days_ago": 75, "title": "Escalation procedure: Blue Yonder Airlines",
     "body": (
        "Escalation procedure for Blue Yonder Airlines (CUST-021)\n"
        "Applies to every Blue Yonder Airlines incident. Read it with the support policy ({policy}) and procedures "
        "CUST-021-PR1 and CUST-021-PR2.\n\n"
        "Who Relecloud calls\n"
        "P1 and P2 incidents: phone {it} (IT Manager) first, then {sponsor} (Finance Director, executive sponsor). "
        "{ops} (Office Manager) is the contact for the corporate head office. Account manager: {am}.\n\n"
        "Corporate and airport systems\n"
        "Relecloud manages corporate endpoints, identity, Microsoft 365 and the corporate network. Airport systems "
        "and their networks belong to Blue Yonder's in-house IT team. When an incident turns out to involve an "
        "airport system, hand it to the in-house IT team through the IT manager and keep the Relecloud ticket open "
        "until the corporate side is confirmed working.\n\n"
        "Security incidents\n"
        "Suspicious sign-ins and malware alerts go to the Relecloud Security and Identity team straight away. Reach "
        "the affected user by phone, not by email (KB0141). A confirmed compromise is P1 and the duty manager "
        "declares a major incident (RB-009); the IT manager is called within 15 minutes.\n\n"
        "Major incidents\n"
        "Platinum tier: P1 incidents are escalated around the clock, every day of the year, with updates to the IT "
        "manager every 30 minutes.\n\n"
        "Changes\n"
        "Every change is agreed with the in-house IT team in the weekly change call and approved by the IT manager "
        "(CUST-021-PR2). The in-house team also keeps its own test device groups; ask before moving devices out of "
        "them.")},
    {"customer": "CUST-014", "version": "2.0", "reviewed_days_ago": 33, "title": "Escalation procedure: Lamna Healthcare",
     "body": (
        "Escalation procedure for Lamna Healthcare (CUST-014)\n"
        "Applies to every Lamna Healthcare incident. Read it with the support policy ({policy}) and procedures "
        "CUST-014-PR1 to CUST-014-PR3.\n\n"
        "Regulated account\n"
        "Lamna Healthcare is a regulated account. Its records are held by the Relecloud Regulated Accounts team, and "
        "changes to them follow that team's process (CUST-014-PR3). Engineers outside the team can read the records "
        "they need but escalate any change through the team. Never record patient information in a ticket, a note "
        "or an email.\n\n"
        "Who Relecloud calls\n"
        "P1 and P2 incidents: phone {it} (IT Manager) first, then {sponsor} (Finance Director, executive sponsor). "
        "{ops} (Office Manager) is the contact for the clinics' opening hours and site access. Account manager: "
        "{am}.\n\n"
        "Clinical systems\n"
        "Clinical systems are hosted and supported by the customer's software vendor. Clinic staff report clinical "
        "system faults to that vendor; Relecloud helps only with the network, the devices and sign-in. If a clinic "
        "cannot reach the clinical system because of the network, that is a Relecloud incident and is P1 when a "
        "whole clinic is affected.\n\n"
        "Escalation hours\n"
        "Gold tier: P1 incidents are escalated around the clock; P2 incidents from 07:00 to 21:00 on weekdays.\n\n"
        "Major incidents\n"
        "Only the duty manager declares a major incident (RB-009). The lead of the Relecloud Regulated Accounts team "
        "joins every major incident bridge for Lamna, and the IT manager is updated every 30 minutes.\n\n"
        "Records and evidence\n"
        "Keep notes factual and free of patient details. If a customer sends a screenshot or file that shows patient "
        "information, remove it from the ticket, tell the IT manager, and record only that a file was removed.\n\n"
        "Account matters\n"
        "Contract and data handling questions go to {am}.")},
    {"customer": "CUST-020", "version": "1.3", "reviewed_days_ago": 64, "title": "Escalation procedure: Consolidated Messenger",
     "body": (
        "Escalation procedure for Consolidated Messenger (CUST-020)\n"
        "Applies to every Consolidated Messenger incident. Read it with the support policy ({policy}), the routing "
        "application configuration notes ({routing}) and procedures CUST-020-PR1 to CUST-020-PR3.\n\n"
        "Dispatch hours\n"
        "Dispatchers need the routing application from 06:00 local time. A routing application outage that stops "
        "dispatchers is P2: phone the operations contact, {ops} (Office Manager), straight away rather than waiting "
        "for email (CUST-020-PR3). Vans that cannot leave the depot make every minute count.\n\n"
        "Who Relecloud calls\n"
        "P1 and P2 incidents: {it} (IT Manager) first, then {sponsor} (Finance Director, executive sponsor). "
        "Operational updates during dispatch go to {ops}. Account manager: {am}.\n\n"
        "Routing application faults\n"
        "Each depot has its own routing application server. Check which depot is affected first: a fault at one depot "
        "points to that depot's server. Certificate warnings follow runbook RB-005 and KB0133. Escalate to the routing "
        "application vendor when the binding or the application itself is at fault, and record the vendor case "
        "number in the ticket.\n\n"
        "Escalation hours\n"
        "Silver tier: P1 and P2 incidents are escalated from 07:00 to 20:00 on weekdays.\n\n"
        "Communication\n"
        "During a dispatch outage, phone the operations contact every 30 minutes until dispatchers can load routes "
        "again, then send a short written summary to the IT manager. A depot that cannot dispatch at all for more "
        "than an hour goes to the duty manager, who decides whether to declare a major incident (RB-009).\n\n"
        "Account matters\n"
        "Contract questions and complaints go to {am}.")},
]

# ===========================================================================
# Configuration notes
# ===========================================================================
CONFIGURATION_DOCUMENTS = [
    {"customer": "CUST-007", "version": "4.0", "reviewed_days_ago": 25,
     "title": "Configuration notes: Woodgrove Bank Secure Gateway summary",
     "body": (
        "Configuration notes: Woodgrove Bank Secure Gateway summary (CUST-007)\n"
        "A summary for service desk engineers. The full gateway configuration is in the Confidential document "
        "Woodgrove-Bank-Secure-Gateway-configuration.docx, attached to the Woodgrove Bank account. That document "
        "carries a sensitivity label: open it only when a network engineer needs it for a change, and never copy "
        "its contents into tickets, notes, chats or customer emails.\n\n"
        "Estate\n"
        "Woodgrove Bank has six sites: the head office and five branches, each with one Secure Gateway appliance. "
        "All six run firmware 10.1.4, rolled out to the branches four weeks ago. Branch managers and the mortgage "
        "team use Remote Access client 4.2.0 when they visit clients, and connect to the head office gateway.\n\n"
        "What the Confidential document holds\n"
        "Public and backup link addressing, the Remote Access profile settings, the administrative access rules and "
        "who holds break-glass access. It records the approved target settings, including changes that are still "
        "waiting for their change window, so always check the running configuration on the gateway itself before "
        "you rely on a value.\n\n"
        "Rules for engineers\n"
        "Administrative access to the gateways is allowed only from the Relecloud network operations range, with "
        "named administrator accounts. Pre-shared keys and certificates are kept in the Relecloud vault, never in "
        "documents or tickets. Tell the bank's IT manager about any firmware change one week ahead (CUST-007-PR3), "
        "and make standard changes in the Tuesday and Thursday window (CUST-007-PR2).\n\n"
        "Remote Access\n"
        "Remote Access client 4.2.0 is deployed to every bank laptop from the Endpoint Agent software library, and "
        "multifactor authentication is required at sign-in. For a connection problem, collect the client version, "
        "the gateway firmware and the client log (Help > Export log) before changing anything, and follow runbook "
        "RB-003 for disconnects.")},
    {"customer": "CUST-020", "version": "2.1", "reviewed_days_ago": 212,
     "title": "Configuration notes: Consolidated Messenger routing application",
     "body": (
        "Configuration notes: Consolidated Messenger routing application (CUST-020)\n"
        "The routing application plans the day's delivery routes for the dispatchers at the north and south depots. "
        "Dispatchers need it from 06:00 local time (CUST-020-PR3).\n\n"
        "Servers\n"
        "Each depot has its own on-premises routing application server, so a fault at one depot does not affect the "
        "other. CMRT-N01 serves the north depot and CMRT-S01 serves the south depot. Both run the same application "
        "version, publish it over HTTPS on the depot network and back up nightly with Relecloud Backup Agent 5.2.1.\n\n"
        "Certificates\n"
        "Each server has its own TLS certificate for its depot's application site, bound in the server's web "
        "configuration. Relecloud renews both certificates under the Fully Managed contract. The certificates are "
        "valid for one year. The south depot certificate was renewed early, when CMRT-S01 was replaced, so the two "
        "certificates no longer expire at the same time. Renewal reminders were set up for the new CMRT-S01; adding "
        "a reminder for CMRT-N01 is still an open action. When a certificate expires, dispatchers at that depot see "
        "a warning that the routing application's security certificate has expired and cannot load routes.\n\n"
        "Support path\n"
        "Certificate warnings follow runbook RB-005 and KB0133: identify the depot and its server, check the "
        "certificate on that server, renew it and bind it to the application site, then ask one dispatcher to confirm "
        "the warning is gone. The routing application vendor supports the application itself and is engaged for "
        "binding or application faults.\n\n"
        "Depot networks\n"
        "Each depot has a Secure Gateway on firmware 10.1.4 and Wi-Fi for the drivers' handheld scanners.")},
    {"customer": "CUST-019", "version": "1.8", "reviewed_days_ago": 47,
     "title": "Configuration notes: A. Datum Corporation backup vault allowance",
     "body": (
        "Configuration notes: A. Datum Corporation backup vault allowance (CUST-019)\n"
        "A. Datum is Co-Managed: Relecloud manages server backup and the cloud vault; A. Datum's IT team supports CAD "
        "workstations and engineers' laptops.\n\n"
        "Protected servers\n"
        "Relecloud Backup Agent 4.9.0 protects the file servers ADCFS01, ADCFS02 and ADCFS03 and the project archive "
        "server ADCARC01. ADCARC01 holds completed project drawings. Each server is backed up every night to the "
        "cloud vault.\n\n"
        "Vault allowance and retention\n"
        "The contracted vault allowance is 3 TB. Usage is normally about 2.5 TB, roughly 83 percent, so a large "
        "import can fill the vault within a night or two. Retention is 60 daily restore points and 12 monthly "
        "restore points. When the vault is full, jobs fail with RBA-2201 and no new recovery points are created; "
        "existing restore points are kept. Follow KB0023 and runbook RB-002.\n\n"
        "Changes and approvals\n"
        "Retention changes and vault allowance increases need written approval from A. Datum's IT manager "
        "(CUST-019-PR3). The account manager, Owen Fletcher, quotes allowance increases. Large archive imports must "
        "be announced to Relecloud a week ahead so the vault can be sized first. Reducing retention to free space "
        "is a temporary measure and also needs the IT manager's written approval.\n\n"
        "Monitoring\n"
        "The backup console alerts the service desk at 90 percent vault usage. Workstations that stop reporting show "
        "as Unknown in the backup dashboard; that is an offline device (KB0039), not a vault problem.\n\n"
        "When jobs fail\n"
        "Read the error code first and follow runbook RB-001. A Silver customer's single failed night is retried "
        "automatically (KB0013); open a ticket when the second run fails. Restores keep working while the vault is "
        "full, from the restore points that already exist.")},
    {"customer": "CUST-013", "version": "3.0", "reviewed_days_ago": 96,
     "title": "Configuration notes: Humongous Insurance claims system",
     "body": (
        "Configuration notes: Humongous Insurance claims system (CUST-013)\n"
        "The claims team uses a document management application to open policy documents during claim intake. "
        "Relecloud provides application support for it under the Fully Managed contract.\n\n"
        "Servers\n"
        "APP03 is the application server that serves the claims document management application, with its "
        "database on the claims database server. APP02 is the retired application server. It is kept running, "
        "read-only, until its document archive has been moved, and it no longer serves users.\n\n"
        "Certificate\n"
        "The application site on APP03 uses a TLS certificate issued for the claims application's address. It is "
        "valid for one year and Relecloud renews it. A certificate renewed or bound on APP02 has no effect on "
        "users. When users see a certificate warning, check the certificate bound on APP03 first (RB-005, KB0133).\n\n"
        "Business hours and priority\n"
        "Claims intake runs from 08:00 to 18:00 local time, with about 25 people in claims intake at peak. An outage "
        "in those hours is P2 or higher (CUST-013-PR3). Service credits are agreed only by the account manager.\n\n"
        "Backups and monitoring\n"
        "APP03 and the database server are backed up every night with Relecloud Backup Agent 5.2.1. Monitoring checks "
        "that the application site answers and warns 30 days before the certificate expires.\n\n"
        "Users and access\n"
        "Claims handlers sign in with their Microsoft 365 accounts through single sign-on; access to the application "
        "comes from the claims application group, approved by the claims manager.\n\n"
        "Changes\n"
        "Changes to APP03 run in the Tuesday and Thursday window (CUST-013-PR2). An emergency certificate change "
        "during claims intake needs the IT manager's approval by phone, recorded in the ticket.")},
    {"customer": "CUST-002", "version": "2.6", "reviewed_days_ago": 9,
     "title": "Configuration notes: Fabrikam Residences Remote Access setup",
     "body": (
        "Configuration notes: Fabrikam Residences Remote Access setup (CUST-002)\n"
        "Most of Fabrikam's 160 users are property managers who work from home or from the buildings they manage, "
        "so Remote Access is their main way into the head office systems.\n\n"
        "Clients and gateways\n"
        "Every property manager's laptop runs Remote Access client 4.2.0, deployed from the Endpoint Agent software "
        "library, with multifactor authentication at sign-in. Clients connect to the head office Secure Gateway. Both "
        "of Fabrikam's gateways, at the head office and the maintenance depot, were upgraded to firmware 10.1.4 in "
        "the most recent weekend maintenance window.\n\n"
        "Profile\n"
        "The Remote Access profile follows the Relecloud standard for Fully Managed customers, with split tunneling "
        "for collaboration traffic (KB0055). The client log is exported from the client's Help menu when needed.\n\n"
        "Maintenance\n"
        "Network maintenance runs on Saturday mornings. Tell the operations contact before any change that can "
        "disconnect remote staff (CUST-002-PR3). Standard changes otherwise follow the Tuesday and Thursday window "
        "(CUST-002-PR2).\n\n"
        "Troubleshooting pointers\n"
        "Collect the client version, the gateway firmware and the client log before changing anything. Do not "
        "reinstall Remote Access clients on 4.x for disconnect problems; it does not help. Runbook RB-003 covers "
        "disconnects that happen about every hour.\n\n"
        "Ownership\n"
        "Remote Access profile and gateway changes belong to the Infrastructure team's network engineers. The L3 "
        "network engineer owns the profile; while that engineer is unavailable, the L2 network engineer leads and "
        "the gateway vendor is engaged if needed (RB-003). On a normal weekday about 120 of the 160 users are "
        "connected remotely, so a fault that disconnects remote staff affects most of the company.")},
    {"customer": "CUST-008", "version": "1.4", "reviewed_days_ago": 133,
     "title": "Configuration notes: Lucerne Publishing payroll application",
     "body": (
        "Configuration notes: Lucerne Publishing payroll application (CUST-008)\n"
        "The finance team runs payroll from an on-premises payroll application. Lucerne is Co-Managed: Lucerne's IT "
        "team administers the payroll application server; Relecloud manages the office network, the Secure Gateway, "
        "backup and Microsoft 365.\n\n"
        "Server and certificate\n"
        "The payroll application runs on Lucerne's application server LPAPP01, separate from the file server FS01. "
        "The application is published over HTTPS with a TLS certificate that Lucerne's IT team renews every year. "
        "Relecloud renews or rebinds it only with the IT manager's approval, agreed in the weekly change call or by "
        "phone in an emergency.\n\n"
        "Users and calendar\n"
        "Four people in the finance team use the payroll application. Payroll is submitted every Thursday, and any "
        "payroll application problem from Tuesday to Thursday is P2 (CUST-008-PR3).\n\n"
        "Support path\n"
        "A certificate warning in the payroll application concerns LPAPP01 and Lucerne's own certificate. Check it "
        "with runbook RB-005 and KB0133, agree the fix with Lucerne's IT manager, and record their approval in the "
        "ticket. This is separate from any other customer's certificate problem, even with the same warning text.\n\n"
        "Backups\n"
        "LPAPP01 and FS01 are backed up every night with Relecloud Backup Agent 5.1.3.\n\n"
        "Network\n"
        "Lucerne has one office behind a Secure Gateway on firmware 10.0.2. Staff who work from home use Remote "
        "Access client 4.1.1. The payroll application is reachable only from the office network and over Remote "
        "Access.\n\n"
        "Approvals\n"
        "Lucerne's IT manager approves changes to the systems Lucerne's team administers, in the weekly change call "
        "(CUST-008-PR2). Record the approval in the ticket before any change to LPAPP01.")},
]


def build_documents(contacts_by_customer: dict[str, list[dict]],
                    procedures_by_customer: dict[str, list[dict]]) -> list[dict]:
    """The 36 documents as plain dicts: code, title, customer, type, version, reviewed_days_ago, body."""
    customer_by_code = {c["code"]: c for c in CUSTOMERS}
    docs: list[dict] = []
    for n, customer in enumerate(CUSTOMERS):
        docs.append({
            "code": f"CDOC-{n + 1:03d}", "customer": customer["code"], "type": "Support policy",
            "title": f"Support policy: {customer['name']}",
            "version": f"{3 + n % 2}.{(n * 3) % 10}", "reviewed_days_ago": 30 + (n * 13) % 150,
            "body": support_policy(customer, contacts_by_customer[customer["code"]],
                                   procedures_by_customer[customer["code"]]),
        })
    policy_code = {d["customer"]: d["code"] for d in docs}
    config_start = len(CUSTOMERS) + len(ESCALATION_DOCUMENTS) + 1
    routing_code = f"CDOC-{config_start + [c['customer'] for c in CONFIGURATION_DOCUMENTS].index('CUST-020'):03d}"
    for spec in ESCALATION_DOCUMENTS:
        customer = customer_by_code[spec["customer"]]
        people = contacts_by_customer[spec["customer"]]
        docs.append({
            "code": f"CDOC-{len(docs) + 1:03d}", "customer": spec["customer"], "type": "Escalation procedure",
            "title": spec["title"], "version": spec["version"], "reviewed_days_ago": spec["reviewed_days_ago"],
            "body": spec["body"].format(policy=policy_code[spec["customer"]], routing=routing_code,
                                        it=_person(people[0]), ops=_person(people[1]), sponsor=_person(people[2]),
                                        am=customer["account_manager"]),
        })
    for spec in CONFIGURATION_DOCUMENTS:
        docs.append({
            "code": f"CDOC-{len(docs) + 1:03d}", "customer": spec["customer"], "type": "Configuration notes",
            "title": spec["title"], "version": spec["version"], "reviewed_days_ago": spec["reviewed_days_ago"],
            "body": spec["body"],
        })
    return docs
