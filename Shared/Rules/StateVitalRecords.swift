import Foundation

/// Who issues a birth certificate, per state.
///
/// Birth records are issued by state or local vital-records offices, and the
/// cost, the accepted ID and the ordering channel differ in every one of them.
/// That variation is the actual moat of this app, and it is also the thing most
/// likely to go quietly stale, so every entry carries the day it was checked and
/// **how** it was checked.
///
/// For a long time this held one state. California was read properly, everywhere
/// else fell back to the federal directory, and Settings said "States with
/// verified detail: CA", which is a sentence that tells a parent in Ohio nothing
/// except that the app has not done its work. The table is now all fifty states
/// and the District of Columbia.
///
/// The rule that produced the one-state version is still the rule, it just has
/// a second gear. **Never bulk import a list of state URLs into here.** Every
/// address below was requested and returned a live page from the state's own
/// domain, and every sentence in an ordering note is something that state's own
/// page says. What differs between entries is depth, and `check` says which:
/// `.pageRead` means the page was read end to end, `.summaryChecked` means the
/// address and the claims were confirmed against the office's own published
/// text without a full read. The UI prints the difference rather than flattening
/// it, because a parent who follows a wrong link to a wrong office loses a
/// fortnight, and the honest version of "we are not certain" is saying so.
///
/// What is deliberately **not** here: fees, processing times, and any office
/// below the state level. Fees and times move constantly and differ by county,
/// which is the same reason `RequirementCatalog` never hardcodes a turnaround.
/// Where a county or town office is faster, the note says so in words and leaves
/// the parent to find their own county, because three thousand guessed county
/// URLs is the failure this file exists to prevent.
struct VitalRecordsOffice: Sendable, Equatable {
    /// How much of this entry somebody has actually stood behind.
    enum Check: String, Sendable, Equatable {
        /// The office's own page was read end to end and the note written from it.
        case pageRead
        /// The address is the office's own and every claim in the note was
        /// confirmed against that office's published text, but nobody has read
        /// the page end to end.
        case summaryChecked
        /// No entry. The national directory stands in, with its state picker.
        case federalFallback
    }

    let stateCode: String
    let officeName: String
    let urlString: String
    /// One or two sentences of what is actually different here. Empty for the
    /// fallback, and empty for the handful of pages that say nothing specific,
    /// because inventing detail is the failure mode this guards.
    let orderingNote: String
    /// The day the entry was last checked. `nil` only for the federal fallback.
    let verifiedOn: Date?
    let check: Check

    var url: URL? { URL(string: urlString) }

    /// True whenever the parent is being sent to their own state's office rather
    /// than to the national directory.
    var isVerified: Bool { check != .federalFallback }

    /// True only where somebody read the whole page. The task detail and the
    /// sources screen say which of the two they are looking at.
    var wasReadInFull: Bool { check == .pageRead }
}

enum StateVitalRecords {
    /// `usa.gov`'s birth-certificate page, which carries a state-by-state picker.
    /// Still the answer for the five territories, which nobody has researched.
    static let federalDirectoryURL = "https://www.usa.gov/birth-certificate"

    /// The day every entry below was last checked.
    static let checkedOn = RequirementCatalog.day(2026, 8, 18)

    /// Every state and the District of Columbia. See the type's own comment for
    /// what may and may not go in here.
    private static let offices: [String: VitalRecordsOffice] = [
        "AL": VitalRecordsOffice(
            stateCode: "AL",
            officeName: "Alabama Department of Public Health, Center for Health Statistics",
            urlString: "https://www.alabamapublichealth.gov/vitalrecords/birth-certificates.html",
            orderingNote: """
            Any county health department in Alabama can issue a certified copy of \
            an Alabama birth certificate, most of them while you wait, so the \
            nearest county office is usually faster than writing to Montgomery. \
            The record is restricted: a parent named on it qualifies, and \
            identification is required. VitalChek is the state's online and \
            telephone channel.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "AK": VitalRecordsOffice(
            stateCode: "AK",
            officeName: "Alaska Department of Health, Health Analytics and Vital Records",
            urlString: "https://health.alaska.gov/en/services/vital-records-orders/",
            orderingNote: """
            There is no county office to fall back on: Anchorage and Juneau are \
            the two counters in the state. A parent listed on the certificate may \
            order; anyone who is not on it needs a notarized letter of consent. \
            Orders are taken in person, by mail, by fax, and online through \
            VitalChek.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "AZ": VitalRecordsOffice(
            stateCode: "AZ",
            officeName: "Arizona Department of Health Services, Bureau of Vital Records",
            urlString: "https://www.azdhs.gov/licensing/vital-records/index.php",
            orderingNote: """
            The state office in Phoenix takes requests in person, by mail and by \
            phone, and VitalChek is its online channel. The page also points to \
            the county health departments, which is worth checking for a recent \
            birth.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "AR": VitalRecordsOffice(
            stateCode: "AR",
            officeName: "Arkansas Department of Health, Vital Records",
            urlString: "https://healthy.arkansas.gov/programs-services/certificates-records/order-birth-records/",
            orderingNote: """
            Arkansas offers vital records services in every county through its \
            local health units, so a walk-in at the county unit is an alternative \
            to the Little Rock office. An acceptable photo ID is required, and \
            there is a mail application and a telephone line as well as online \
            ordering.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "CA": VitalRecordsOffice(
            stateCode: "CA",
            officeName: "California Department of Public Health, Vital Records",
            urlString: "https://www.cdph.ca.gov/Programs/CHSI/Pages/Vital-Records.aspx",
            orderingNote: """
            California issues both authorized certified copies and informational \
            copies. Only the authorized copy establishes identity, and only a \
            parent named on the record (or a short list of other relatives) may \
            request one. The request has to carry a notarized sworn statement \
            unless it is made in person. County recorders in the county of birth \
            are usually faster than the state office for a recent birth.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "CO": VitalRecordsOffice(
            stateCode: "CO",
            officeName: "Colorado Department of Public Health and Environment, Vital Records",
            urlString: "https://cdphe.colorado.gov/vitalrecords",
            orderingNote: """
            Requests go to the state office in person or by mail, with VitalChek \
            as the telephone and online channel. Several county public health \
            agencies issue certified copies as well, which is usually the shorter \
            route for a recent birth.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "CT": VitalRecordsOffice(
            stateCode: "CT",
            officeName: "Connecticut Department of Public Health, State Vital Records Office",
            urlString: "https://portal.ct.gov/dph/vital-records/birth-certificates",
            orderingNote: """
            For a birth from 2003 onwards, any town vital records office in \
            Connecticut can issue a certified copy, and the town is generally \
            quicker than the state office. A valid government photo ID is \
            required, or two documents from the state's alternative list. \
            Eligibility runs to the parents, the person themselves at eighteen, \
            and a short list of relatives.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "DE": VitalRecordsOffice(
            stateCode: "DE",
            officeName: "Delaware Division of Public Health, Office of Vital Statistics",
            urlString: "https://www.dhss.delaware.gov/dhss/dph/ss/vitalstats.html",
            orderingNote: """
            Delaware runs three walk-in locations as well as taking mailed \
            requests at the Dover office, and it offers parents a way to pre-order \
            a newborn's certificate rather than waiting to apply afterwards.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "DC": VitalRecordsOffice(
            stateCode: "DC",
            officeName: "DC Health, Vital Records Division",
            urlString: "https://dchealth.dc.gov/service/birth-certificates",
            orderingNote: """
            The District issues the long-form certificate only. Identification \
            matching the name on the record is required, and orders are taken by \
            mail, by phone and online through VitalChek.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "FL": VitalRecordsOffice(
            stateCode: "FL",
            officeName: "Florida Department of Health, Bureau of Vital Statistics",
            urlString: "https://www.floridahealth.gov/certificates-records/birth-certificates/",
            orderingNote: """
            A Florida birth record stays confidential for 125 years: the parents \
            named on it, the registrant at eighteen, and legal guardians or \
            representatives qualify, and anybody else needs a notarized affidavit \
            from somebody who does. Valid photo ID is required. County health \
            departments issue records from 1917 onwards, which usually beats \
            writing to Jacksonville. VitalChek is the online vendor.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "GA": VitalRecordsOffice(
            stateCode: "GA",
            officeName: "Georgia Department of Public Health, State Office of Vital Records",
            urlString: "https://dph.georgia.gov/ways-request-vital-record/birth",
            orderingNote: """
            Certified copies come from the county vital records office or from the \
            state office, and the county is the shorter route. A parent ordering \
            has to be named on the certificate and show a government photo ID \
            carrying a signature. Georgia approves three online vendors rather \
            than one.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "HI": VitalRecordsOffice(
            stateCode: "HI",
            officeName: "Hawaii Department of Health, Vital Records",
            urlString: "https://health.hawaii.gov/vitalrecords/birth-marriage-certificates/",
            orderingNote: """
            Hawaii takes orders through its own state portal rather than a \
            third-party vendor, and a government-issued photo ID is required. \
            There is an issuance office in Honolulu for anybody who can go in \
            person.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "ID": VitalRecordsOffice(
            stateCode: "ID",
            officeName: "Idaho Department of Health and Welfare, Bureau of Vital Records and Health Statistics",
            urlString: "https://healthandwelfare.idaho.gov/services-programs/birth-marriage-death-records/ordering-birth-certificate",
            orderingNote: """
            The bureau has no public counter, so a certified copy is ordered \
            online or by mail rather than collected. Access is restricted to the \
            person named, immediate family and anybody who can show a tangible \
            interest.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "IL": VitalRecordsOffice(
            stateCode: "IL",
            officeName: "Illinois Department of Public Health, Division of Vital Records",
            urlString: "https://dph.illinois.gov/topics-services/birth-death-other-records/birth-records.html",
            orderingNote: """
            The person named on the record at eighteen, a parent shown on it, or a \
            legal guardian or representative with written evidence may order. The \
            state office takes requests in person, by mail, by phone and by email, \
            and it publishes a directory of county clerks, who hold the local copy \
            of a record filed in their county.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "IN": VitalRecordsOffice(
            stateCode: "IN",
            officeName: "Indiana Department of Health, Division of Vital Records",
            urlString: "https://www.in.gov/health/vital-records/",
            orderingNote: """
            The department says plainly that walk-in service is not available at \
            the state office and that ordering through the local health department \
            where the birth happened is faster. VitalChek is the only online \
            vendor it authorizes.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "IA": VitalRecordsOffice(
            stateCode: "IA",
            officeName: "Iowa Department of Health and Human Services, Bureau of Health Statistics",
            urlString: "https://hhs.iowa.gov/family-community/vital-records",
            orderingNote: """
            Iowa is the notarization state: unless the application is handed over \
            in person it has to be notarized, and it needs a current government \
            photo ID with it. County recorders act as local registrars and hold \
            the records for births in their county.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "KS": VitalRecordsOffice(
            stateCode: "KS",
            officeName: "Kansas Department of Health and Environment, Office of Vital Statistics",
            urlString: "https://www.kdhe.ks.gov/1165/Office-of-Vital-Statistics",
            orderingNote: """
            Copies go to the person named, immediate family, a legal \
            representative, or somebody who can show a direct interest. Walk-in \
            and mail requests go to Topeka, and the office contracts with a single \
            vendor for internet orders.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "KY": VitalRecordsOffice(
            stateCode: "KY",
            officeName: "Kentucky Cabinet for Health and Family Services, Office of Vital Statistics",
            urlString: "https://www.chfs.ky.gov/agencies/dph/dehp/vsb/Pages/default.aspx",
            orderingNote: """
            Orders are taken in person, by mail, through a drop box at the visitor \
            entrance, and online through VitalChek, and a valid photo ID is needed \
            to collect a will-call order. Kentucky's county and circuit clerks \
            hold old marriage and divorce records, not birth records, so the state \
            office is the route.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "LA": VitalRecordsOffice(
            stateCode: "LA",
            officeName: "Louisiana Department of Health, Vital Records Registry",
            urlString: "https://ldh.la.gov/page/how-to-order-birth-records",
            orderingNote: """
            Louisiana is a closed-record state: a parent, the adult registrant, a \
            sibling, a grandparent or a grandchild may order, and an attorney \
            needs a written declaration of representation. Participating Clerks of \
            Court around the state issue certified copies, and internet, fax and \
            telephone orders go through VitalChek.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "ME": VitalRecordsOffice(
            stateCode: "ME",
            officeName: "Maine Center for Disease Control and Prevention, Division of Data, Research, and Vital Statistics",
            urlString: "https://www.maine.gov/dhhs/mecdc/public-health-systems/data-research/vital-records/index.shtml",
            orderingNote: """
            Most municipal offices in Maine hold vital records as well as the \
            state office, so the town office is worth trying before Augusta. \
            Certified copies go to eligible applicants only.
            """,
            verifiedOn: checkedOn,
            check: .pageRead
        ),
        "MD": VitalRecordsOffice(
            stateCode: "MD",
            officeName: "Maryland Department of Health, Division of Vital Records",
            urlString: "https://health.maryland.gov/vsa/Pages/birth.aspx",
            orderingNote: """
            The person named, a parent named on the certificate, a court-appointed \
            guardian, or a representative of one of them may order. Same-day \
            service needs an unexpired government photo ID showing an issue and an \
            expiry date; without one, two alternative documents are required \
            instead.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "MA": VitalRecordsOffice(
            stateCode: "MA",
            officeName: "Massachusetts Department of Public Health, Registry of Vital Records and Statistics",
            urlString: "https://www.mass.gov/ordering-a-certificate",
            orderingNote: """
            Two places hold the record: the Registry in Dorchester holds the \
            statewide copy and the city or town clerk holds the local one, and \
            either can issue. A mailed request has to carry a photocopy of the \
            requester's government photo ID.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "MI": VitalRecordsOffice(
            stateCode: "MI",
            officeName: "Michigan Department of Health and Human Services, Vital Records",
            urlString: "https://www.michigan.gov/mdhhs/doing-business/vitalrecords",
            orderingNote: """
            A Michigan birth record stays restricted for 100 years, so eligibility \
            has to be shown rather than assumed: the person, a parent, a legal \
            guardian or a representative. The state takes orders online and by \
            mail, and the county clerk where the birth happened is the other \
            route.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "MN": VitalRecordsOffice(
            stateCode: "MN",
            officeName: "Minnesota Department of Health, Office of Vital Records",
            urlString: "https://www.health.state.mn.us/people/vitalrecords/index.html",
            orderingNote: """
            Minnesota releases a certified copy only to somebody with a tangible \
            interest in the record, and the request has to be signed in front of a \
            notary or in front of county vital records staff. County offices issue \
            as well as the state.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "MS": VitalRecordsOffice(
            stateCode: "MS",
            officeName: "Mississippi State Department of Health, Vital Records",
            urlString: "https://msdh.ms.gov/page/31,0,109.html",
            orderingNote: """
            Requests go to the Ridgeland office in person or by mail, by \
            telephone, or online through the service the department contracts \
            with.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "MO": VitalRecordsOffice(
            stateCode: "MO",
            officeName: "Missouri Department of Health and Senior Services, Bureau of Vital Records",
            urlString: "https://health.mo.gov/data/vitalrecords/",
            orderingNote: """
            Requests go to the Bureau of Vital Records in Jefferson City by mail \
            or in person, and Missouri also issues many records through local \
            public health agencies once the state has registered them.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "MT": VitalRecordsOffice(
            stateCode: "MT",
            officeName: "Montana Department of Public Health and Human Services, Office of Vital Records",
            urlString: "https://dphhs.mt.gov/vitalrecords/",
            orderingNote: """
            Orders go to the Helena office by mail, or through the two vendors the \
            office contracts with. It names them rather than leaving it open, so a \
            site that is not one of the two is not the state's channel.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NE": VitalRecordsOffice(
            stateCode: "NE",
            officeName: "Nebraska Department of Health and Human Services, Vital Records",
            urlString: "https://dhhs.ne.gov/pages/vital-records.aspx",
            orderingNote: """
            Nebraska releases a certified copy to the person on the record and to \
            applicants who can show a proper purpose, with a current government \
            photo ID. Orders are taken online, by mail and in person in Lincoln.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NV": VitalRecordsOffice(
            stateCode: "NV",
            officeName: "Nevada Division of Public and Behavioral Health, Office of Vital Records",
            urlString: "https://www.dpbh.nv.gov/programs/vitalrecords/",
            orderingNote: """
            Birth records are confidential in Nevada and go only to a qualified \
            applicant: the registrant, a direct family member by blood or \
            marriage, a guardian, or a legal representative. The state office \
            issues birth records; the county recorders issue marriage records, \
            which is a common wrong turn.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NH": VitalRecordsOffice(
            stateCode: "NH",
            officeName: "New Hampshire Department of State, Division of Vital Records Administration",
            urlString: "https://sos.nh.gov/vital-records-0",
            orderingNote: """
            New Hampshire keeps vital records with the Secretary of State rather \
            than with the health department, which is worth knowing before \
            searching. City and town clerks issue certified copies as well as the \
            Concord office, and an application needs photo identification with it.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NJ": VitalRecordsOffice(
            stateCode: "NJ",
            officeName: "New Jersey Department of Health, Office of Vital Statistics and Registry",
            urlString: "https://www.nj.gov/health/vital/",
            orderingNote: """
            A request has to carry proof of your relationship to the person on the \
            record as well as a copy of your own ID. The local registrar of the \
            municipality where the birth happened can issue in person; otherwise \
            it is the state office in Trenton.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NM": VitalRecordsOffice(
            stateCode: "NM",
            officeName: "New Mexico Department of Health, Vital Records",
            urlString: "https://www.nmhealth.org/about/erd/bvrhs/vrp/birth/",
            orderingNote: """
            New Mexico restricts access to the registrant, immediate family, and \
            anybody with tangible proof of legal interest, and it lists exactly \
            who counts as immediate family. The state does not take cards \
            directly, so online orders go through VitalChek.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NY": VitalRecordsOffice(
            stateCode: "NY",
            officeName: "New York State Department of Health, Bureau of Vital Records",
            urlString: "https://www.health.ny.gov/vital_records/birth.htm",
            orderingNote: """
            New York is two systems, and this is the one that does not cover New \
            York City. A birth in Manhattan, Brooklyn, Queens, the Bronx or Staten \
            Island is a New York City Department of Health record and has to be \
            ordered from the city, not from Albany. Everywhere else in the state \
            is here.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "NC": VitalRecordsOffice(
            stateCode: "NC",
            officeName: "North Carolina Department of Health and Human Services, NC Vital Records",
            urlString: "https://vitalrecords.nc.gov/order.htm",
            orderingNote: """
            The register of deeds in the county where the birth happened can \
            usually issue a certified copy the same day, which is the fast route; \
            the state office in Raleigh is the slower one.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "ND": VitalRecordsOffice(
            stateCode: "ND",
            officeName: "North Dakota Health and Human Services, Division of Vital Records",
            urlString: "https://www.hhs.nd.gov/vital/birth",
            orderingNote: """
            North Dakota's list is short: the person named on the record, once \
            they are sixteen, or a parent named on it. The state's own secure \
            online application is the quickest channel.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "OH": VitalRecordsOffice(
            stateCode: "OH",
            officeName: "Ohio Department of Health, Bureau of Vital Statistics",
            urlString: "https://odh.ohio.gov/about-us/offices-bureaus-and-departments/bvs/bureau-of-vital-statistics",
            orderingNote: """
            Any local health district in Ohio can issue a certified copy of any \
            Ohio birth, not only of the ones registered in that district, and each \
            district sets its own fee. The state office in Columbus takes mail \
            orders.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "OK": VitalRecordsOffice(
            stateCode: "OK",
            officeName: "Oklahoma State Department of Health, Vital Records Service",
            urlString: "https://oklahoma.gov/health/services/birth-and-death-certificates/birth-certificates.html",
            orderingNote: """
            Every applicant has to send a copy of a government photo ID, and more \
            may be asked for to show entitlement. Orders are taken online and by \
            telephone, with will-call pickup for anybody who can get to the \
            office.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "OR": VitalRecordsOffice(
            stateCode: "OR",
            officeName: "Oregon Health Authority, Center for Health Statistics",
            urlString: "https://www.oregon.gov/oha/ph/birthdeathcertificates/pages/orderbirthcertificate.aspx",
            orderingNote: """
            Certified copies come from the county where the birth happened as well \
            as from the state office, and counties commonly handle recent births. \
            Orders are taken online, in person, by phone and by mail, and Oregon \
            issues only to a qualified applicant.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "PA": VitalRecordsOffice(
            stateCode: "PA",
            officeName: "Pennsylvania Department of Health, Division of Vital Records",
            urlString: "https://www.pa.gov/agencies/health/programs/vital-records/birth-certificates",
            orderingNote: """
            Pennsylvania restricts a birth record for 105 years, so the applicant \
            has to be eligible, show valid identification and sign the \
            application. The Commonwealth authorizes exactly one online vendor, \
            reached through its own health.pa.gov address.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "RI": VitalRecordsOffice(
            stateCode: "RI",
            officeName: "Rhode Island Department of Health, Center for Vital Records",
            urlString: "https://health.ri.gov/vital-records",
            orderingNote: """
            For a birth from 1960 onwards, any city or town clerk in Rhode Island \
            can issue the certificate, as can the Center for Vital Records in \
            Cranston. A valid government photo ID is required to show you are \
            entitled to it.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "SC": VitalRecordsOffice(
            stateCode: "SC",
            officeName: "South Carolina Department of Public Health, Division of Vital Records",
            urlString: "https://www.dph.sc.gov/public/vital-records/about-vital-records",
            orderingNote: """
            Requests go to the Columbia office in person or by mail, or online \
            through the state's vendor. County health departments issue a \
            short-form birth card rather than the full certified copy, which is \
            not always the document another office will accept.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "SD": VitalRecordsOffice(
            stateCode: "SD",
            officeName: "South Dakota Department of Health, Vital Records",
            urlString: "https://doh.sd.gov/licensing-and-records/vital-records/",
            orderingNote: """
            Certified copies can be collected in person at a county Register of \
            Deeds office as well as from the Pierre office, and orders are also \
            taken by mail, by phone and online.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "TN": VitalRecordsOffice(
            stateCode: "TN",
            officeName: "Tennessee Department of Health, Office of Vital Records",
            urlString: "https://www.tn.gov/health/vr.html",
            orderingNote: """
            Any county health department can issue any Tennessee birth certificate \
            the state holds, so there is no need to travel to the county of birth. \
            Identification is required when the application is handed over, and \
            Tennessee authorizes a single card vendor for online orders.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "TX": VitalRecordsOffice(
            stateCode: "TX",
            officeName: "Texas Department of State Health Services, Vital Statistics",
            urlString: "https://www.dshs.texas.gov/vital-statistics",
            orderingNote: """
            Texas issues only to a properly qualified applicant, and it defines \
            the term: the person, a parent, a spouse, a sibling, a child, a \
            grandparent, a guardian, or a legal agent. The state runs its own \
            ordering site, and the local registrar where the birth was registered \
            is the other counter.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "UT": VitalRecordsOffice(
            stateCode: "UT",
            officeName: "Utah Department of Health and Human Services, Office of Vital Records and Statistics",
            urlString: "https://vitalrecords.utah.gov/order-a-vital-record-certificate",
            orderingNote: """
            Certificates go to the person of record, immediate family, guardians \
            and designated legal representatives, and a family member may be asked \
            to prove the relationship with another certificate. Most Utah local \
            health departments take in-person orders as well as the state office.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "VT": VitalRecordsOffice(
            stateCode: "VT",
            officeName: "Vermont Department of Health, Vital Records",
            urlString: "https://www.healthvermont.gov/stats/vital-records/order-vital-records",
            orderingNote: """
            The town or city clerk is the cheapest and quickest route in Vermont \
            and can issue certified copies going back to 1909; the state also \
            sells certified copies online. Valid identification is required for a \
            certified copy.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "VA": VitalRecordsOffice(
            stateCode: "VA",
            officeName: "Virginia Department of Health, Office of Vital Records",
            urlString: "https://www.vdh.virginia.gov/vital-records/",
            orderingNote: """
            Every request needs a legible copy of the requester's identification \
            and a signature. Virginia is unusual in also issuing vital records at \
            DMV customer service centres, which is often the quickest counter.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "WA": VitalRecordsOffice(
            stateCode: "WA",
            officeName: "Washington State Department of Health, Center for Health Statistics",
            urlString: "https://doh.wa.gov/licenses-permits-and-certificates/vital-records/ordering-vital-record/birth-record",
            orderingNote: """
            Local health jurisdictions and county offices issue as well as the \
            state office, and an in-person request at either is often same-day. \
            What each local office offers varies, so it is worth checking before \
            driving.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "WV": VitalRecordsOffice(
            stateCode: "WV",
            officeName: "West Virginia Department of Health, Vital Registration Office",
            urlString: "https://dhhr.wv.gov/HSC/VR/CR/Pages/default.aspx",
            orderingNote: """
            In-person requests at the Charleston office are same-day. A mailed \
            request needs a colour copy of your identification, and the office \
            takes check or money order only. County clerks hold locally filed \
            records.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "WI": VitalRecordsOffice(
            stateCode: "WI",
            officeName: "Wisconsin Department of Health Services, Vital Records Office",
            urlString: "https://www.dhs.wisconsin.gov/vitalrecords/index.htm",
            orderingNote: """
            Wisconsin county Register of Deeds offices issue birth records as well \
            as the Madison office, and walk-in service in Madison is usually \
            same-day. A mailed application needs a photocopy of an acceptable \
            photo ID; VitalChek handles online and telephone orders.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        ),
        "WY": VitalRecordsOffice(
            stateCode: "WY",
            officeName: "Wyoming Department of Health, Vital Statistics Services",
            urlString: "https://health.wyo.gov/admin/vitalstatistics/",
            orderingNote: """
            Certified copies go to the registrant, either parent named on the \
            certificate, a legal guardian, or a lawyer for one of them. Wyoming \
            runs its own online portal, with mail forms for anybody who cannot use \
            it.
            """,
            verifiedOn: checkedOn,
            check: .summaryChecked
        )
    ]

    static func office(for stateCode: String) -> VitalRecordsOffice {
        let code = stateCode.uppercased()
        if let entry = offices[code] { return entry }
        return VitalRecordsOffice(
            stateCode: code,
            officeName: code.isEmpty
                ? "Your state's vital records office"
                : "\(USState.displayName(for: code)) vital records office",
            urlString: federalDirectoryURL,
            orderingNote: "",
            verifiedOn: nil,
            check: .federalFallback
        )
    }

    /// Every entry, in state order, for the screen that shows the working.
    static var allOffices: [VitalRecordsOffice] {
        offices.values.sorted { $0.stateCode < $1.stateCode }
    }

    static var verifiedStateCodes: [String] {
        offices.keys.sorted()
    }

    /// The states whose page somebody has read end to end, as opposed to
    /// checked. Surfaced in Settings, because the difference is the honest part.
    static var fullyReadStateCodes: [String] {
        offices.values.filter(\.wasReadInFull).map(\.stateCode).sorted()
    }
}
