#!/usr/bin/env python3
"""
Generates 10 fictional employee XML files for the Bulk XML Import project.
Author: Senthil P N. (senpnathan@gmail.com)
All people, IDs and phone numbers are made up. Output is deterministic (fixed seed).

    python tools/generate_sample_xml.py            # writes ../sample-data/xml/
"""
import random, os
from datetime import date, timedelta
import xml.etree.ElementTree as ET

rnd = random.Random(2026)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sample-data", "xml")
os.makedirs(OUT, exist_ok=True)
TODAY = date(2026, 9, 29)

# ---- reference pools ---------------------------------------------------------
LOC = {  # location: (city, state, country, currency, postal prefix)
    "London":    ("London", "England", "United Kingdom", "GBP", "EC1"),
    "Sydney":    ("Sydney", "NSW", "Australia", "AUD", "2000"),
    "Toronto":   ("Toronto", "ON", "Canada", "CAD", "M5V"),
    "Singapore": ("Singapore", "", "Singapore", "SGD", "0189"),
    "Berlin":    ("Berlin", "BE", "Germany", "EUR", "10115"),
    "Remote":    ("Lisbon", "", "Portugal", "USD", "1000"),
}
SKILLS = {
    "Engineering": [("C#", "Programming"), ("T-SQL", "Database"), ("Python", "Programming"), ("Azure", "Cloud"), ("Docker", "DevOps"), ("REST APIs", "Architecture"), ("Git", "Tooling")],
    "IT Services": [("Windows Server", "Infrastructure"), ("Active Directory", "Infrastructure"), ("PowerShell", "Scripting"), ("Networking", "Infrastructure"), ("Backup & Recovery", "Operations")],
    "Human Resources": [("Recruitment", "Talent"), ("Employee Relations", "People"), ("Payroll", "Operations"), ("HRIS", "Systems"), ("Onboarding", "Talent")],
    "Finance": [("Excel", "Analysis"), ("Financial Modelling", "Analysis"), ("Power BI", "Reporting"), ("Budgeting", "Planning"), ("IFRS", "Compliance")],
    "Sales": [("Negotiation", "Selling"), ("CRM", "Tools"), ("Pipeline Management", "Selling"), ("Presentation", "Communication")],
    "Marketing": [("SEO", "Digital"), ("Content Strategy", "Content"), ("Google Analytics", "Analytics"), ("Copywriting", "Content")],
    "Customer Support": [("Zendesk", "Tools"), ("Troubleshooting", "Support"), ("Communication", "Soft skills"), ("SLA Management", "Operations")],
    "Operations": [("Process Improvement", "Operations"), ("Vendor Management", "Procurement"), ("Scheduling", "Planning")],
    "Data & Analytics": [("SQL", "Database"), ("Python", "Programming"), ("Tableau", "Reporting"), ("Statistics", "Analysis")],
    "Executive": [("Strategy", "Leadership"), ("Budgeting", "Planning"), ("Stakeholder Management", "Leadership")],
}
CERTS = [("AWS Certified Solutions Architect", "Amazon Web Services"), ("Microsoft Certified: Azure Administrator", "Microsoft"),
         ("PMP", "Project Management Institute"), ("CIPD Level 5", "CIPD"), ("CPA", "CPA Australia"), ("ITIL 4 Foundation", "Axelos"),
         ("Certified Scrum Master", "Scrum Alliance"), ("CompTIA Security+", "CompTIA"), ("Google Analytics Certification", "Google")]
COURSES = [("Advanced T-SQL Performance Tuning", "Pluralsight", 16), ("Leadership Essentials", "Dale Carnegie", 24), ("Data Privacy & GDPR", "Internal Academy", 4),
           ("Cloud Fundamentals", "Microsoft Learn", 12), ("Effective Communication", "Coursera", 8), ("Workplace Health & Safety", "Internal Academy", 3),
           ("Agile Project Delivery", "Scrum.org", 16), ("Excel for Analysts", "LinkedIn Learning", 10)]
ASSETS = [("Laptop", "14-inch business laptop"), ("Monitor", "27-inch 4K monitor"), ("Mobile Phone", "Company smartphone"),
          ("Access Card", "Building access card"), ("Headset", "Noise-cancelling headset")]
PROJECTS = [("PRJ-1001", "Customer Portal Rebuild"), ("PRJ-1002", "Data Warehouse Migration"), ("PRJ-1003", "HR Self-Service Portal"),
            ("PRJ-1004", "Mobile App v2"), ("PRJ-1005", "Compliance Audit 2026"), ("PRJ-9000", "Internal / Administration")]
TASKS = ["Development", "Code review", "Stakeholder meeting", "Documentation", "Testing", "Planning", "Support tickets", "Data analysis", "Training delivery"]
LEAVE = [("Annual", "Family holiday"), ("Annual", "Long weekend"), ("Sick", "Flu"), ("Sick", "Medical appointment"),
         ("Study", "Exam preparation"), ("Bereavement", "Family matter"), ("Unpaid", "Personal travel")]
DEGREES = [("Bachelor of Science", "Computer Science"), ("Bachelor of Commerce", "Accounting"), ("Bachelor of Arts", "Communications"),
           ("Master of Business Administration", "Management"), ("Bachelor of Engineering", "Information Technology"), ("Diploma", "Business Administration")]
UNIS = ["University of Leeds", "University of Sydney", "University of Toronto", "National University of Singapore", "Technical University of Berlin", "University of Lisbon"]
PRIOR = ["Northwind Systems", "Globex Consulting", "Initech Solutions", "Hooli Digital", "Umbrella Retail", "Stark Logistics"]
LEAVE_REASONS = ["New role", "Career growth", "Relocation", "Contract ended", "Restructure"]
GOALS = ["Deliver Q4 roadmap; mentor two juniors", "Improve process cycle time by 15%", "Complete leadership training; own team OKRs", "Reduce ticket backlog by 20%"]
COMMENTS = ["Consistently exceeds expectations and collaborates well.", "Solid performance; needs to delegate more.",
            "Strong technical depth and reliable delivery.", "Great customer focus; improve documentation habits."]
BASE = {"E9": 185000, "E5": 118000, "E4": 92000, "M3": 98000, "F3": 76000, "S3": 82000, "M4": 105000, "C2": 52000, "I4": 79000, "D1": 62000}

# no, title, first, middle, last, gender, dob, dept, jobtitle, grade, type, location, hire, manager, status, marital, nationality
E = [
 (1001, "Ms", "Amelia", "Grace", "Hart", "Female", date(1978, 3, 14), "Executive", "Managing Director", "E9", "Full-time", "London", date(2016, 2, 1), None, "Active", "Married", "British"),
 (1002, "Mr", "Rahul", "", "Menon", "Male", date(1988, 7, 22), "Engineering", "Senior Software Engineer", "E5", "Full-time", "Remote", date(2019, 6, 17), 1001, "Active", "Married", "Indian"),
 (1003, "Mr", "José", "Luis", "Álvarez", "Male", date(1991, 11, 5), "Engineering", "DevOps Engineer", "E4", "Full-time", "Berlin", date(2021, 1, 11), 1001, "Active", "Single", "Spanish"),
 (1004, "Ms", "Sarah", "", "O'Connor", "Female", date(1985, 9, 30), "Human Resources", "HR Manager", "M3", "Full-time", "Sydney", date(2018, 4, 9), 1001, "Active", "Married", "Australian"),
 (1005, "Mr", "Wei", "", "Chen", "Male", date(1993, 1, 19), "Finance", "Financial Analyst", "F3", "Full-time", "Singapore", date(2022, 8, 1), 1001, "Active", "Single", "Singaporean"),
 (1006, "Ms", "Priya", "Anand", "Nair", "Female", date(1990, 5, 8), "Sales", "Account Executive", "S3", "Full-time", "Toronto", date(2020, 3, 2), 1001, "On Leave", "Married", "Canadian"),
 (1007, "Mr", "Liam", "", "Fischer", "Male", date(1987, 12, 2), "Marketing", "Marketing & Growth Lead", "M4", "Full-time", "Berlin", date(2019, 10, 14), 1001, "Active", "Divorced", "German"),
 (1008, "Ms", "Zoë", "", "Williams", "Female", date(1996, 4, 27), "Customer Support", "Support Specialist", "C2", "Contract", "Remote", date(2024, 2, 5), 1004, "Active", "Single", "Portuguese"),
 (1009, "Mr", "Omar", "", "Haddad", "Male", date(1984, 6, 16), "IT Services", "Systems Administrator", "I4", "Full-time", "London", date(2017, 9, 4), 1003, "Terminated", "Married", "British"),
 (1010, "Ms", "Grace", "", "Kim", "Female", date(2000, 8, 12), "Data & Analytics", "Junior Data Analyst", "D1", "Full-time", "Sydney", date(2025, 7, 21), 1005, "Active", "Single", "Australian"),
]


def sub(parent, tag, val=None):
    e = ET.SubElement(parent, tag)
    if val is not None:
        e.text = str(val)
    return e


def d(x):
    return x.isoformat() if x else None


def rdate(a, b):
    return a + timedelta(days=rnd.randint(0, max(1, (b - a).days)))


def ascii_name(s):
    return s.lower().replace("é", "e").replace("ë", "e").replace("á", "a").replace("'", "")


def fill(parent, pairs):
    for tag, val in pairs:
        sub(parent, tag, val)


def build(row):
    no, title, first, mid, last, gender, dob, dept, jt, grade, etype, loc, hire, mgr, status, marital, nat = row
    city, state, country, cur, pc = LOC[loc]
    term = date(2026, 6, 30) if status == "Terminated" else None
    end = term or TODAY
    root = ET.Element("Employee")

    # -- Demographics -----------------------------------------------------------
    fill(sub(root, "Demographics"), [
        ("EmployeeNo", no), ("EmployeeCode", f"EMP-{no}"), ("Active", 0 if term else 1), ("Title", title),
        ("FirstName", first), ("MiddleName", mid), ("LastName", last), ("DateOfBirth", d(dob)), ("Gender", gender),
        ("MaritalStatus", marital), ("Nationality", nat), ("NationalID", f"NID{rnd.randint(10**8, 10**9 - 1)}"),
        ("PassportNo", None if no % 3 == 0 else f"P{rnd.randint(10**6, 10**7 - 1)}"),   # empty tag on purpose
        ("TaxID", f"TAX{rnd.randint(10**7, 10**8 - 1)}"), ("BloodGroup", rnd.choice(["A+", "B+", "O+", "AB+", "O-", "A-"])),
        ("Email", f"{ascii_name(first)}.{ascii_name(last)}@example.com"), ("PersonalEmail", f"{ascii_name(first)}{no}@mail.example.org"),
        ("WorkPhone", f"+00 555 {rnd.randint(1000, 9999)}"), ("Mobile", f"+00 7{rnd.randint(100, 999)} {rnd.randint(100000, 999999)}"),
        ("HireDate", d(hire)), ("ProbationEndDate", d(hire + timedelta(days=90))), ("TerminationDate", d(term)),  # empty for active staff
        ("EmploymentType", etype), ("Department", dept), ("JobTitle", jt), ("Grade", grade),
        ("ManagerEmployeeNo", mgr), ("WorkLocation", loc), ("Status", status)])

    # -- Addresses --------------------------------------------------------------
    fill(sub(root, "Address"), [
        ("AddressType", "Home"), ("Line1", f"{rnd.randint(1, 220)} {rnd.choice(['Park', 'Rose', 'Station', 'Oak', 'Harbour'])} Street"),
        ("Line2", f"Unit {rnd.randint(1, 40)}" if no % 2 else None), ("City", city), ("State", state),
        ("PostalCode", f"{pc}{rnd.randint(10, 99)}"), ("Country", country), ("IsPrimary", 1)])
    if no % 3 == 1:
        fill(sub(root, "Address"), [("AddressType", "Postal"), ("Line1", f"PO Box {rnd.randint(100, 999)}"), ("City", city),
                                    ("State", state), ("PostalCode", pc + "00"), ("Country", country), ("IsPrimary", 0)])

    # -- Emergency contacts -----------------------------------------------------
    for i in range(rnd.randint(1, 2)):
        fill(sub(root, "EmergencyContact"), [
            ("Name", rnd.choice(["Alex", "Sam", "Jordan", "Taylor", "Morgan", "Robin"]) + " " + last),
            ("Relationship", rnd.choice(["Spouse", "Parent", "Sibling", "Friend"])), ("Phone1", f"+00 555 {rnd.randint(1000, 9999)}"),
            ("Phone2", None), ("Email", f"contact{no}{i}@mail.example.org"), ("Address", f"{city}, {country}")])

    # -- Dependents -------------------------------------------------------------
    for _ in range(rnd.choice([1, 2, 3]) if marital in ("Married", "Divorced") and no % 2 == 0 else 0):
        fill(sub(root, "Dependent"), [
            ("Name", f"{rnd.choice(['Ava', 'Noah', 'Mia', 'Leo', 'Ivy', 'Kai'])} {last}"), ("Relationship", rnd.choice(["Child", "Spouse"])),
            ("DateOfBirth", d(rdate(date(2005, 1, 1), date(2022, 12, 31)))), ("Gender", rnd.choice(["Female", "Male"])),
            ("InsuranceCovered", rnd.choice([1, 1, 0]))])

    # -- Qualifications ---------------------------------------------------------
    for i in range(rnd.randint(1, 3)):
        deg, fld = rnd.choice(DEGREES)
        fill(sub(root, "Qualification"), [
            ("Degree", deg), ("FieldOfStudy", fld), ("Institution", rnd.choice(UNIS)), ("YearCompleted", dob.year + 22 + i * 2),
            ("GradeOrScore", rnd.choice(["First Class", "2:1", "Distinction", "GPA 3.6", "GPA 3.8"]))])

    # -- Work history (none for the graduate hire) ------------------------------
    if no != 1010:
        s = hire
        for i in range(rnd.randint(1, 3)):
            e_ = s - timedelta(days=rnd.randint(30, 120))
            s = e_ - timedelta(days=rnd.randint(500, 1300))
            fill(sub(root, "WorkHistory"), [
                ("Company", rnd.choice(PRIOR)), ("JobTitle", ("Junior " if i else "") + jt.split(" ", 1)[-1]),
                ("StartDate", d(s)), ("EndDate", d(e_)),
                ("Responsibilities", f"Delivered {dept.lower()} objectives, worked with cross-functional teams & reported to senior management."),
                ("ReasonForLeaving", rnd.choice(LEAVE_REASONS))])

    # -- Skills -----------------------------------------------------------------
    for name, cat in rnd.sample(SKILLS[dept], k=min(len(SKILLS[dept]), rnd.randint(3, 5))):
        fill(sub(root, "Skill"), [("SkillName", name), ("Category", cat),
                                  ("ProficiencyLevel", rnd.choice(["Intermediate", "Advanced", "Expert"])),
                                  ("YearsExperience", round(rnd.uniform(1, 12), 1))])

    # -- Certifications ---------------------------------------------------------
    for name, body in rnd.sample(CERTS, k=rnd.choice([0, 1, 2, 3])):
        iss = rdate(hire - timedelta(days=700), TODAY - timedelta(days=60))
        fill(sub(root, "Certification"), [
            ("CertificationName", name), ("IssuingBody", body), ("IssueDate", d(iss)),
            ("ExpiryDate", None if name == "PMP" else d(iss + timedelta(days=365 * 3))),
            ("CredentialID", f"CRD-{rnd.randint(10**5, 10**6 - 1)}")])

    # -- Salary history ---------------------------------------------------------
    sal = BASE[grade] * 0.82
    eff = hire
    first_row = True
    while eff <= end:
        fill(sub(root, "SalaryHistory"), [
            ("EffectiveDate", d(eff)), ("BaseSalary", f"{sal:.2f}"), ("Currency", cur), ("PayFrequency", "Annual"),
            ("Bonus", None if first_row else f"{sal * 0.05:.2f}"),
            ("Reason", "Starting salary" if first_row else rnd.choice(["Annual review", "Promotion", "Market adjustment"]))])
        sal *= rnd.uniform(1.04, 1.09)
        eff = date(eff.year + 1, 7, 1)
        first_row = False

    # -- Leave ------------------------------------------------------------------
    for lt_, why in rnd.sample(LEAVE, k=rnd.randint(2, 5)):
        st = rdate(max(hire, date(2024, 1, 1)), end - timedelta(days=10))
        days = rnd.choice([1, 2, 3, 5, 10])
        fill(sub(root, "Leave"), [
            ("LeaveType", lt_), ("StartDate", d(st)), ("EndDate", d(st + timedelta(days=days - 1))), ("Days", f"{days}.0"),
            ("Status", rnd.choice(["Approved", "Approved", "Pending"])), ("ApprovedBy", "Amelia Hart" if no != 1001 else None), ("Reason", why)])

    # -- Performance reviews ----------------------------------------------------
    yr = hire.year + 1
    while yr <= min(2025, end.year) and yr - hire.year <= 3:
        fill(sub(root, "PerformanceReview"), [
            ("ReviewPeriod", f"FY{yr}"), ("ReviewDate", d(date(yr, 12, 10))),
            ("Reviewer", "Amelia Hart" if no != 1001 else "Board of Directors"), ("Rating", f"{rnd.uniform(2.8, 5.0):.1f}"),
            ("Goals", rnd.choice(GOALS)), ("Comments", rnd.choice(COMMENTS))])
        yr += 1

    # -- Training ---------------------------------------------------------------
    for name, prov, hrs in rnd.sample(COURSES, k=rnd.randint(1, 4)):
        fill(sub(root, "Training"), [
            ("CourseName", name), ("Provider", prov), ("CompletedDate", d(rdate(hire, end))), ("DurationHours", f"{hrs}.0"),
            ("Cost", f"{hrs * rnd.choice([0, 15, 25, 40]):.2f}"), ("Result", rnd.choice(["Passed", "Passed", "Attended"]))])

    # -- Assets -----------------------------------------------------------------
    for i, (typ, desc) in enumerate(rnd.sample(ASSETS, k=rnd.randint(1, 3))):
        fill(sub(root, "Asset"), [("AssetTag", f"AST-{no}-{i + 1}"), ("AssetType", typ), ("Description", desc),
                                  ("IssuedDate", d(hire + timedelta(days=i))), ("ReturnedDate", d(term))])

    # -- Timesheets: header + entries -------------------------------------------
    wk = date(2026, 6, 1)  # a Monday
    for w in range(rnd.randint(1, 3)):
        start = wk + timedelta(weeks=w)
        if term and start > term:
            break
        ts = sub(root, "Timesheet")
        fill(ts, [("WeekStartDate", d(start)), ("Status", rnd.choice(["Approved", "Approved", "Submitted"])),
                  ("ApprovedBy", "Amelia Hart" if no != 1001 else None)])
        for day in range(5):
            code, pname = rnd.choice(PROJECTS)
            fill(sub(ts, "Entry"), [
                ("WorkDate", d(start + timedelta(days=day))), ("ProjectCode", code), ("ProjectName", pname),
                ("Task", rnd.choice(TASKS)), ("Hours", f"{rnd.choice([6, 7, 7.5, 8, 8.5]):.2f}"),
                ("Notes", None if day % 2 else "R&D <internal> work")])   # exercises XML escaping
    return root


for row in E:
    root = build(row)
    ET.indent(root, space="  ")
    path = os.path.join(OUT, f"Employee_{row[0]}.xml")
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
    print("wrote", os.path.basename(path))
