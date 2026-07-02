This document is the **field-by-field reference** that accompanies the [Household Data Co-Location tech spec](https://windfalldata.atlassian.net/wiki/spaces/Platform/pages/4026204162). It maps each enrichment trigger to:

* The corresponding source field(s) in the household build (`people.all`)
* The flattened **Enrichment Field** (the column name in the enrichment source table)
* The data type, grain, and any date-dependency notes

For the architectural context (single owner-keyed enrichment source table, separate employment table, pipeline design), see the tech spec.

---

## Output Tables

| Table | Key | Contents | Field grains |
| --- | --- | --- | --- |
| **Enrichment source table**  | `owner_id`  | Denormalized household + person data. Household fields duplicated per owner.  | H, P, B  |
| **Employment source table**  | `employment_id`  | Career/employment data. Separate ID space, no FK to enrichment table.  | E  |

### Field Origin (Grain)

The grain column indicates where the data comes from in the build SQL and how it appears in the output:

* **H** — Household-origin field. Duplicated across all owners in the household. Sourced from `household_triggers.sql`, `properties.sql`, `household_donations.sql`.
* **P** — Person-origin field. Unique per owner. No household-level aggregation. Sourced from `owners.sql`, `extended_triggers.sql` (`owner_extended_triggers` CTE).
* **B** — Both. Each row in the enrichment source table carries **two columns**: the per-owner value AND the household-level `LOGICAL_OR` aggregation. Used for interest/lifestyle boolean flags where both individual targeting and household-level filtering are needed.
* **E** — Employment table field. Stored in the separate employment source table, keyed on `employment_id`. Not on the enrichment source table.

### Legend (additional column markers)

* **DERIVED** — computed during enrichment from multiple source fields; may not map to a single column
* **EXTERNAL** — comes from external data sources during enrichment; no source field equivalent in `people.all`
* **DATE-SOURCE** — raw date field to pull. The trigger is computed by comparing this date against a threshold at enrichment time. Pull the date, NOT pre-computed boolean flags (those may be stale).
* **FLAG (skip)** — pre-computed boolean derived from a date field. Do NOT pull; recompute from the date at enrichment time.

---

## Data Sizing

The following sizes are from a **prototype run** of an earlier design that materialized only the household-grain data. The current single-table denormalized design (one row per owner, with household data duplicated per owner) will be larger — the multiplier is roughly the average number of owners per household (typically 1-2x).

| Metric | Value | Notes |
| --- | --- | --- |
| Source table (`people.all`)  | \~460 GB  | Nested  |
| Prototype enrichment source table (BigQuery)  | \~39.59 GB  | Household-grain only, no per-owner denormalization  |
| Prototype as Avro (500 files)  | \~55 GB  |  |
| Compression ratio (prototype vs source)  | \~8.6%  |  |
| **Production denormalized table size**  | TBD  | Expected \~1-2x prototype  |
| **Employment source table size**  | TBD  | Separate table  |

* **Prototype table ID:** `windfall-dev-329123.ps_scratch.prod-triggers-test1`
* **Source snapshot:** `windfall-production.people.all_20260331`

---

## Trigger Configuration

| Enrichment Trigger | Enrichment Field | Type | Grain | Source Field(s) | Date Dep. | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Recent Mover  | `recentMoveDate`  | DATE  | H  | `recentPurchaseDate`, `owners.consumers.householdAttributes.recentlyMovedYear` + `recentlyMovedMonth`  | DATE-SOURCE  | Threshold: 6mo. `recentlyMovedFlag` is FLAG (skip)  |
| Recently Divorced  | `recentDivorceDate`  | DATE  | H  | `recentDivorceDate`, `owners.divorceDate`  | DATE-SOURCE  | Threshold: 6mo. `householdAttributes.recentDivorce` is FLAG (skip)  |
| Recent Death in Family  | `recentDeathDate`  | DATE  | H  | `recentDeathDate`, `owners.deathDate`  | DATE-SOURCE  | Threshold: 6mo  |
| Pilot License  | `hasPilotLicense`  | BOOLEAN  | P  | `owners.faaCertifications` → derive `isPilot = true` for any cert  | —  | Per-person: FAA certs are per-owner  |
| Boat Owner  | `isBoatOwner`  | BOOLEAN  | H  | `isBoatOwner`  | —  | Top-level flag already available  |
| Boat Company Name  | `boatCompanyName`  | STRING  | H  | `properties.boats.nameOfVessel` → pick primary boat  | —  | Derive from primary boat record  |
| Boat Class (Length)  | `boatClass`  | STRING  | H  | `properties.boats.boatClass` → pick primary boat  | —  |  |
| Boat Age  | `boatAgeYears`  | INTEGER  | H  | `properties.boats.ageYears` → pick primary boat  | —  |  |
| Boat Last Seen  | `boatYearsSinceLastSeen`  | INTEGER  | H  | `properties.boats.yearsSinceLastSeen` → pick primary boat  | —  |  |
| Boat Sports License  | `hasBoatSportsLicense`  | BOOLEAN  | H  | `owners.sportsLicenses` → ANY `hasSportsLicense = true`  | —  |  |
| Boat Fishing License  | `hasBoatFishingLicense`  | BOOLEAN  | H  | `owners.sportsLicenses` → ANY `hasFishingLicense = true`  | —  |  |
| Boat Saltwater License  | `hasBoatSaltwaterLicense`  | BOOLEAN  | H  | `owners.sportsLicenses` → ANY `hasSaltwaterLicense = true`  | —  |  |
| Plane Owner  | `isPlaneOwner`  | BOOLEAN  | H  | `isPlaneOwner`  | —  | Top-level flag already available  |
| Multi-property Owner  | `isMultiPropertyOwner`  | BOOLEAN  | H  | `isMultiPropertyOwner`  | —  |  |
| Rental Property Owner  | `isRentalPropertyOwner`  | BOOLEAN  | H  | `isRentalPropertyOwner`  | —  |  |
| Philanthropic Giver  | `recentPhilanthropicGiftDate`  | DATE  | H  | `recentPhilanthropicGiftDate`  | DATE-SOURCE  | Threshold: 120mo. Derived from `owners.donations.date` (philanthropic)  |
| Has Household Debt  | `isHouseholdDebt`  | BOOLEAN  | H  | `isHouseholdDebt`  | —  |  |
| (companion)  | `totalHouseholdDebt`  | INTEGER  | H  | `totalHouseholdDebt`  | —  |  |
| Political Donor  | `recentPoliticalDonationDate`  | DATE  | H  | `recentPoliticalContributionDate`  | DATE-SOURCE  | Threshold: 6mo. Derived from `owners.donations.date` (political)  |
| Political Party (household)  | `politicalParty`  | STRING  | H  | `politicalParty` (top-level)  | —  | Household-level; distinct from person-level `owners.politicalParty`  |
| Political Party (person)  | `politicalPartyIndividual`  | STRING  | P  | `owners.politicalParty`, `owners.consumers.individualAttributes.politicalPartyIndividual`  | —  | Per-owner; may differ from household-level  |
| Small Business Owner  | `isSmallBusinessOwner`  | BOOLEAN  | H  | `isSmallBusinessOwnerV2`  | —  | Use V2; V1 is legacy  |
| Primary Property LTV  | `primaryPropertyLoanToValue`  | FLOAT  | H  | `primaryPropertyLoanToValue`  | —  |  |
| Trust Association  | `hasTrust`  | BOOLEAN  | H  | `hasTrust`  | —  |  |
| Donor Advised Funds  | `donationHasDafAffiliation`  | BOOLEAN  | H  | `hasDAFAffiliation`  | —  |  |
| NTEE Codes  | `donationNteeCodes`  | STRING\[\]  | H  | `nteeCodes`  | DATE-SOURCE  | Threshold: 120mo. Pre-aggregated; donation dates needed to refilter  |
| Regional Focus  | `donationRregionalFocuses`  | STRING\[\]  | H  | `regionalFocuses`  | DATE-SOURCE  | Threshold: 120mo. Pre-aggregated; donation dates needed to refilter  |
| Foundation Association  | `recentFoundationAssociationDate`  | DATE  | H  | `recentFoundationAssociationDate`  | DATE-SOURCE  | Threshold: 120mo. `hasFoundationAssociation` is FLAG (skip)  |
| Foundation Ownership  | `foundationOwnershipDate`  | DATE  | H  | `foundationOwnershipDate`  | DATE-SOURCE  | Threshold: 120mo  |
| Foundation Officer/Trustee  | `recentFoundationTrusteeDate`  | DATE  | H  | `recentFoundationTrusteeDate`  | DATE-SOURCE  | Threshold: 120mo. `isFoundationOfficer` is FLAG (skip)  |
| Top Philanthropic Donor  | `topPhilanthropicDonorPriorYearAmount`  | FLOAT  | H  | **DERIVED** from `owners.donations`  | DATE-SOURCE  | Sum philanthropic donations in prior calendar year. Threshold: 10000  |
| Top Political Donor  | `topPoliticalDonorPriorYearAmount`  | FLOAT  | H  | **DERIVED** from `owners.donations` (political)  | DATE-SOURCE  | Sum political donations in prior calendar year. Threshold: 10000  |
| Nonprofit Board Member  | `isNonprofitBoardMember`  | BOOLEAN  | H  | `isCharityBoardMember`  | —  |  |
| Primary Property AVM  | `primaryPropertyAvm`  | INTEGER  | H  | `primaryPropertyAvm`  | —  |  |
| Occupation  | `occupation`  | STRING  | P  | `owners.consumers.occupation` or `owners.consumers.individualAttributes.occupationIndividual`  | —  | Per-person via `owners.sql`  |
| Gender  | `gender`  | STRING  | P  | `owners.gender`  | —  | Per-person via `owners.sql`  |
| Money in Motion  | `moneyInMotionAmount`  | FLOAT  | H  | **DERIVED** from SEC transactions, property sales, mortgages  | DATE-SOURCE  | Threshold: 1yr / 10000  |
| Liquidity Trigger  | `hasLiquidityTrigger`  | BOOLEAN  | H  | **DERIVED**  | DATE-SOURCE  | Computed from financial signals with time windows  |
| Windfall Trigger  | `hasWindfallTrigger`  | BOOLEAN  | H  | **DERIVED**  | DATE-SOURCE  | Computed from financial signals with time windows  |
| Recent Mortgage  | `recentMortgageDate`  | DATE  | H  | `mostRecentMortgageRecordingDate`  | DATE-SOURCE  | Threshold: 6mo  |
| Primary Car Make  | `primaryCarMake`  | STRING  | H  | `primaryCarMake`  | —  | Already top-level  |
| Primary Car Model  | `primaryCarModel`  | STRING  | H  | `primaryCarModel`  | —  | Already top-level  |
| Luxury Car Owner  | `isLuxuryCarOwner`  | BOOLEAN  | H  | `isLuxuryCarOwner`  | —  |  |
| Imported Car Owner  | `isImportedCarOwner`  | BOOLEAN  | H  | `isImportedCarOwner`  | —  |  |
| Number of Vehicles  | `numberOfVehicles`  | INTEGER  | H  | `numberOfVehicles`  | —  |  |
| Accredited Investor  | `isAccreditedInvestor`  | BOOLEAN  | H  | **DERIVED** from `netWorth`  | —  | SEC threshold check  |
| Household Accredited Investor  | `isHouseholdAccreditedInvestor`  | BOOLEAN  | H  | **DERIVED** from household net worth  | —  |  |
| Household Income  | `householdIncome`  | INTEGER  | H  | `owners.consumers.financialAttributes.income`  | —  |  |
| Income Range  | `incomeRange`  | STRING  | H  | `owners.consumers.financialAttributes.incomeDescription`  | —  |  |
| Number of Properties  | `numberOfProperties`  | INTEGER  | H  | **DERIVED** — count of `properties` array  | —  |  |
| Number of Units  | `totalUnits`  | INTEGER  | H  | **DERIVED** — sum of `properties.units`  | —  |  |
| Number SFR Properties  | `numberOfSfrProperties`  | INTEGER  | H  | **DERIVED** — count `properties` where type = SFR  | —  |  |
| Number SFR Units  | `numberOfSfrUnits`  | INTEGER  | H  | **DERIVED** — sum units for SFR properties  | —  |  |
| Total Value SFRs  | `totalValueSfrProperties`  | INTEGER  | H  | **DERIVED** — sum `properties.estimatedValue` for SFR  | —  |  |
| % Net Worth in SFRs  | `percentNetWorthInSfrs`  | FLOAT  | H  | **DERIVED** — SFR value / `netWorth`  | —  |  |
| Residences Acquired Last 5yr  | `residencesAcquiredLast5Years`  | INTEGER  | H  | **DERIVED** — count `properties` where `lastSaleDate` within 5yr  | DATE-SOURCE  | Uses `properties.lastSaleDate`  |
| Portfolio LTV  | `realEstatePortfolioLtv`  | FLOAT  | H  | **DERIVED** from `properties.loanToValue`, `properties.mortgageDetails`  | —  |  |
| 5-11 MFR Properties  | `numberOfMfr5to11Properties`  | INTEGER  | H  | **DERIVED** — count `properties` where units 5-11  | —  |  |
| 5-11 MFR Units  | `numberOfMfr5to11Units`  | INTEGER  | H  | **DERIVED** — sum units for 5-11 unit properties  | —  |  |
| 12+ MFR Properties  | `numberOfMfr12PlusProperties`  | INTEGER  | H  | **DERIVED** — count `properties` where units >= 12  | —  |  |
| 12+ MFR Units  | `numberOfMfr12PlusUnits`  | INTEGER  | H  | **DERIVED** — sum units for 12+ unit properties  | —  |  |
| Has Boat Access  | `hasBoatAccess`  | BOOLEAN  | H  | **DERIVED** from `properties.boats`, `owners.sportsLicenses`  | —  |  |
| Has Boat Lift  | `hasBoatLift`  | BOOLEAN  | H  | **DERIVED / EXTERNAL**  | —  | May not be in source  |
| Mid-Market ($100k-$499k)  | `isMidMarket100kTo499k`  | BOOLEAN  | H  | **DERIVED** from `netWorth`  | —  | Range check  |
| Mid-Market ($500k-$999k)  | `isMidMarket500kTo999k`  | BOOLEAN  | H  | **DERIVED** from `netWorth`  | —  | Range check  |
| Liquid Net Worth  | `liquidNetWorth`  | INTEGER  | H  | **DERIVED**  | —  |  |
| Investable Assets  | `investableAssets`  | INTEGER  | H  | **DERIVED**  | —  |  |
| Investable Assets Range  | `investableAssetsRange`  | STRING  | H  | **DERIVED**  | —  |  |
| Crypto Interest  | `hasInterestInCrypto`  | BOOLEAN  | H  | `hasInterestInCrypto`  | —  |  |
| Direct Mail Responders  | `isDirectMailResponder`  | BOOLEAN  | H  | **DERIVED** — ANY `owners.dmResponses` exists  | —  | Don't keep full list, just flag  |
| Primary Address Incorrect  | `isPrimaryAddressIncorrect`  | BOOLEAN  | H  | **DERIVED / EXTERNAL**  | —  | Address validation result  |
| Lot Size  | `lotSizeSqFt`  | INTEGER  | H  | `owners.consumers.propertyAttributes.landSquareFootage`  | —  |  |
| Building Size  | `buildingSizeSqFt`  | INTEGER  | H  | `properties.squareFootage`  | —  |  |
| Building-to-Lot Ratio  | `buildingToLotRatio`  | FLOAT  | H  | **DERIVED** — building / lot size  | —  |  |
| Property Type  | `propertyType`  | STRING  | H  | `properties.propertyType` (primary property)  | —  |  |
| Property Latitude  | `propertyLatitude`  | FLOAT  | H  | `latitude`  | —  | Top-level = primary property  |
| Property Longitude  | `propertyLongitude`  | FLOAT  | H  | `longitude`  | —  | Top-level = primary property  |
| Company Owned  | `isCompanyOwned`  | BOOLEAN  | H  | `properties.companyOwned` (primary property)  | —  |  |
| Owner Occupied  | `isOwnerOccupied`  | BOOLEAN  | H  | `properties.ownerOccupied` (primary property)  | —  |  |
| Tax Year Assessed  | `taxYearAssessed`  | INTEGER  | H  | `properties.taxYear` (primary property)  | —  |  |
| Tax Assessed Value  | `taxAssessedValue`  | INTEGER  | H  | `properties.taxAssessedValue` (primary property)  | —  |  |
| Tax Billed Amount  | `taxBilledAmount`  | FLOAT  | H  | `properties.taxBilledAmount` (primary property)  | —  |  |
| Year Built  | `yearBuilt`  | INTEGER  | H  | `properties.yearBuilt` (primary property)  | —  |  |
| Last Sale Date  | `lastSaleDate`  | DATE  | H  | `properties.lastSaleDate` (primary property)  | DATE-SOURCE  | Also used by Recent Mover, Residences Acquired  |
| Last Sale Amount  | `lastSaleAmount`  | INTEGER  | H  | `properties.lastSaleAmount` (primary property)  | —  |  |
| Prior Sale Date  | `priorSaleDate`  | DATE  | H  | `properties.priorSaleDate` (primary property)  | DATE-SOURCE  |  |
| Prior Sale Amount  | `priorSaleAmount`  | INTEGER  | H  | `properties.priorSaleAmount` (primary property)  | —  |  |
| Last Owner Transfer Date  | `lastOwnerTransferDate`  | DATE  | H  | `properties.lastOwnershipTransferDate` (primary property)  | DATE-SOURCE  |  |
| Square Footage  | `squareFootage`  | INTEGER  | H  | `properties.squareFootage` (primary property)  | —  |  |
| Bedroom Count  | `bedroomCount`  | INTEGER  | H  | `properties.bedrooms` (primary property)  | —  |  |
| Bathroom Count  | `bathroomCount`  | FLOAT  | H  | `properties.bathrooms` (primary property)  | —  |  |
| Room Count  | `roomCount`  | INTEGER  | H  | `properties.rooms` (primary property)  | —  |  |
| Number of Stories  | `numberOfStories`  | INTEGER  | H  | `properties.stories` (primary property)  | —  |  |
| Number of Units (property)  | `propertyUnits`  | INTEGER  | H  | `properties.units` (primary property)  | —  |  |
| Estimated Property Value  | `estimatedPropertyValue`  | INTEGER  | H  | `properties.estimatedValue` (primary property)  | —  |  |

---

## Extended Triggers

> **Date dependency:** None of the Extended Triggers have date-dependent thresholds. All are static attribute lookups.
>
> **Grain note:** Extended triggers in this section follow the standard grain marking:
>
> * **H** — household-only (e.g., `dwellingType`, `householdSize`)
> * **P** — person-only, not aggregated to household (e.g., `maritalStatus`, `age`, `education`, `collegeGraduate`)
> * **B** — both per-owner value AND `LOGICAL_OR`'d household value, both stored on the row (most interest/lifestyle flags)
> 

| # | Enrichment Trigger | Enrichment Field | Type | Grain | Source Field(s) |
| --- | --- | --- | --- | --- | --- |
| 1  | Dwelling Type  | `dwellingType`  | STRING  | H  | `owners.consumers.householdAttributes.dwellingType`  |
| 2  | Length of Residence  | `lengthOfResidence`  | INTEGER  | H  | `owners.consumers.householdAttributes.lengthOfResidence`  |
| 3  | Household Size  | `householdSize`  | INTEGER  | H  | `owners.consumers.householdAttributes.householdSize`  |
| 4  | Number of Adults  | `numberOfAdults`  | INTEGER  | H  | `owners.consumers.householdAttributes.numberOfAdults`  |
| 5  | Number of Children  | `numberOfChildren`  | INTEGER  | H  | `owners.consumers.householdAttributes.numberOfChildren`  |
| 6  | New Teen Driver Gender  | `newTeenDriverGender`  | STRING  | H  | `owners.consumers.householdAttributes.newTeenDriverGender`  |
| 7  | Generations in Household  | `generationsInHousehold`  | INTEGER  | H  | `owners.consumers.householdAttributes.generationsInHousehold`  |
| 8  | Marital Status  | `maritalStatus`  | STRING  | P  | `owners.consumers.householdAttributes.maritalStatus`  |
| 9  | Home Air Conditioning  | `homeAirConditioning`  | STRING  | H  | `owners.consumers.propertyAttributes.homeAirConditioning`  |
| 10  | Home Water Source  | `homeWaterSource`  | STRING  | H  | `owners.consumers.propertyAttributes.homeWater`  |
| 11  | Home Sewer Type  | `homeSewerType`  | STRING  | H  | `owners.consumers.propertyAttributes.homeSewer`  |
| 12  | Lines of Credit  | `linesOfCredit`  | INTEGER  | H  | `owners.consumers.financialAttributes.linesOfCredit`  |
| 13  | Age  | `age`  | INTEGER  | P  | `owners.consumers.age`  |
| 14  | Education  | `education`  | STRING  | P  | `owners.consumers.individualAttributes.educationIndividual`  |
| 15  | Young Adult In Household  | `youngAdultInHousehold`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.youngAdultInHousehold`  |
| 16  | Senior Adult In Household  | `seniorAdultInHousehold`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.seniorAdultInHousehold`  |
| 17  | Children Present  | `childrenPresent`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.childrenPresent`  |
| 18  | College Graduate  | `collegeGraduate`  | BOOLEAN  | P  | `owners.consumers.householdAttributes.collegeGraduate`  |
| 19  | Christian Families  | `christianFamilies`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.christianFamilies`  |
| 20  | Working Woman  | `workingWoman`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.workingWoman`  |
| 21  | Veteran Present In Household  | `veteranPresentInHousehold`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.veteranPresentInHousehold`  |
| 22  | Credit Card User  | `creditCardUser`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.creditCardUser`  |
| 23  | Mail Order Buyer  | `mailOrderBuyer`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.mailOrderBuyer`  |
| 24  | Mail Order Responder  | `mailOrderResponder`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.mailOrderResponder`  |
| 25  | Pet Owner  | `petOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.petOwner`  |
| 26  | Cat Owner  | `catOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.catOwner`  |
| 27  | Dog Owner  | `dogOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.dogOwner`  |
| 28  | Other Pet Owner  | `otherPetOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.otherPetOwner`  |
| 29  | New Teen Driver  | `newTeenDriver`  | BOOLEAN  | H  | `owners.consumers.householdAttributes.newTeenDriver`  |
| 30  | Truck Owner  | `truckOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.truckOwner`  |
| 31  | Motorcycle Owner  | `motorcycleOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.motorcycleOwner`  |
| 32  | RV Owner  | `rvOwner`  | BOOLEAN  | B  | `owners.consumers.householdAttributes.rvOwner`  |
| 33  | Home Swimming Pool  | `homeSwimmingPool`  | BOOLEAN  | H  | `owners.consumers.propertyAttributes.homeSwimmingPool`  |
| 34  | CC American Express  | `ccAmericanExpress`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccAmericanExpress`  |
| 35  | CC American Express Gold Platinum  | `ccAmericanExpressGoldPlatinum`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccAmericanExpressGoldPlatinum`  |
| 36  | CC Discover  | `ccDiscover`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccDiscover`  |
| 37  | CC Visa  | `ccVisa`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccVisa`  |
| 38  | CC Mastercard  | `ccMastercard`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccMastercard`  |
| 39  | CC Bank  | `ccBank`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccBank`  |
| 40  | CC Gas Dept Retail  | `ccGasDeptRetail`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccGasDeptRetail`  |
| 41  | CC Travel Entertainment  | `ccTravelEntertainment`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccTravelEntertainment`  |
| 42  | CC Unknown  | `ccUnknown`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccUnknown`  |
| 43  | CC Gold Platinum  | `ccGoldPlatinum`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccGoldPlatinum`  |
| 44  | CC Premium  | `ccPremium`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccPremium`  |
| 45  | CC Upscale Dept  | `ccUpscaleDept`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccUpscaleDept`  |
| 46  | CC New Issue  | `ccNewIssue`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.ccNewIssue`  |
| 47  | Home Living  | `homeLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.homeLiving`  |
| 48  | DIY Living  | `diyLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.diyLiving`  |
| 49  | Sporty Living  | `sportyLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportyLiving`  |
| 50  | Upscale Living  | `upscaleLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.upscaleLiving`  |
| 51  | Cultural Artistic Living  | `culturalArtisticLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.culturalArtisticLiving`  |
| 52  | Highbrow  | `highbrow`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.highbrow`  |
| 53  | Common Living  | `commonLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.commonLiving`  |
| 54  | Professional Living  | `professionalLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.professionalLiving`  |
| 55  | Broader Living  | `broaderLiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.broaderLiving`  |
| 56  | Arts  | `arts`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.arts`  |
| 57  | Theater Performing Arts  | `theaterPerformingArts`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.theaterPerformingArts`  |
| 58  | Food Wines  | `foodWines`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.foodWines`  |
| 59  | Foods Natural  | `foodsNatural`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.foodsNatural`  |
| 60  | Cooking General  | `cookingGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.cookingGeneral`  |
| 61  | Cooking Gourmet  | `cookingGourmet`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.cookingGourmet`  |
| 62  | Aviation  | `aviation`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.aviation`  |
| 63  | Auto Work  | `autoWork`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.autoWork`  |
| 64  | Automotive Buff  | `automotiveBuff`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.automotiveBuff`  |
| 65  | Beauty Cosmetics  | `beautyCosmetics`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.beautyCosmetics`  |
| 66  | Career  | `career`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.career`  |
| 67  | Career Improvement  | `careerImprovement`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.careerImprovement`  |
| 68  | Parenting  | `parenting`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.parenting`  |
| 69  | Childrens Interests  | `childrensInterests`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.childrensInterests`  |
| 70  | Grandchildren  | `grandchildren`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.grandchildren`  |
| 71  | Community Charities  | `communityCharities`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.communityCharities`  |
| 72  | Religious Inspirational  | `religiousInspirational`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.religiousInspirational`  |
| 73  | Crafts  | `crafts`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.crafts`  |
| 74  | Photography  | `photography`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.photography`  |
| 75  | Sewing Knitting Needlework  | `sewingKnittingNeedlework`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sewingKnittingNeedlework`  |
| 76  | Collector Avid  | `collectorAvid`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectorAvid`  |
| 77  | Collectibles Grouping  | `collectiblesGrouping`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesGrouping`  |
| 78  | Collectibles General  | `collectiblesGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesGeneral`  |
| 79  | Collectibles Stamps  | `collectiblesStamps`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesStamps`  |
| 80  | Collectibles Coins  | `collectiblesCoins`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesCoins`  |
| 81  | Collectibles Arts  | `collectiblesArts`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesArts`  |
| 82  | Collectibles Antiques  | `collectiblesAntiques`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesAntiques`  |
| 83  | Collectibles Sports Memorabilia  | `collectiblesSportsMemorabilia`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.collectiblesSportsMemorabilia`  |
| 84  | Education Online  | `educationOnline`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.educationOnline`  |
| 85  | Exercise Aerobic  | `exerciseAerobic`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.exerciseAerobic`  |
| 86  | Exercise Running Jogging  | `exerciseRunningJogging`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.exerciseRunningJogging`  |
| 87  | Exercise Walking  | `exerciseWalking`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.exerciseWalking`  |
| 88  | High Tech General  | `highTechGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.highTechGeneral`  |
| 89  | Games Computer Games  | `gamesComputerGames`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.gamesComputerGames`  |
| 90  | Games Video Games  | `gamesVideoGames`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.gamesVideoGames`  |
| 91  | Games Board Puzzles  | `gamesBoardPuzzles`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.gamesBoardPuzzles`  |
| 92  | Gaming Casino  | `gamingCasino`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.gamingCasino`  |
| 93  | Consumer Electronics  | `consumerElectronics`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.consumerElectronics`  |
| 94  | Environmental Issues  | `environmentalIssues`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.environmentalIssues`  |
| 95  | Gardening  | `gardening`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.gardening`  |
| 96  | Home Furnishings Decorating  | `homeFurnishingsDecorating`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.homeFurnishingsDecorating`  |
| 97  | House Plant  | `housePlant`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.housePlant`  |
| 98  | Home Improvement  | `homeImprovement`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.homeImprovement`  |
| 99  | Home Improvement DIY  | `homeImprovementDiy`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.homeImprovementDiy`  |
| 100  | Health Medical  | `healthMedical`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.healthMedical`  |
| 101  | Dieting Weight Loss  | `dietingWeightLoss`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.dietingWeightLoss`  |
| 102  | Self Improvement  | `selfImprovement`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.selfImprovement`  |
| 103  | Investments Foreign  | `investmentsForeign`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.investmentsForeign`  |
| 104  | Investments Personal  | `investmentsPersonal`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.investmentsPersonal`  |
| 105  | Investments Real Estate  | `investmentsRealEstate`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.investmentsRealEstate`  |
| 106  | Investments Stocks Bonds  | `investmentsStocksBonds`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.investmentsStocksBonds`  |
| 107  | Money Seekers  | `moneySeekers`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.moneySeekers`  |
| 108  | Sweepstakes Contests  | `sweepstakesContests`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sweepstakesContests`  |
| 109  | Music Home Stereo  | `musicHomeStereo`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.musicHomeStereo`  |
| 110  | Music Player  | `musicPlayer`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.musicPlayer`  |
| 111  | Music Collector  | `musicCollector`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.musicCollector`  |
| 112  | Music Listener  | `musicListener`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.musicListener`  |
| 113  | Movie Grouping  | `movieGrouping`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.movieGrouping`  |
| 114  | Movie Music General  | `movieMusicGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.movieMusicGeneral`  |
| 115  | Movie Collector  | `movieCollector`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.movieCollector`  |
| 116  | Current Affairs Politics  | `currentAffairsPolitics`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.currentAffairsPolitics`  |
| 117  | History Military  | `historyMilitary`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.historyMilitary`  |
| 118  | Outdoor Enthusiast General  | `outdoorEnthusiastGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.outdoorEnthusiastGeneral`  |
| 119  | Outdoor Fishing  | `outdoorFishing`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.outdoorFishing`  |
| 120  | Outdoor Boating Sailing  | `outdoorBoatingSailing`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.outdoorBoatingSailing`  |
| 121  | Outdoor Camping Hiking  | `outdoorCampingHiking`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.outdoorCampingHiking`  |
| 122  | Outdoor Hunting Shooting  | `outdoorHuntingShooting`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.outdoorHuntingShooting`  |
| 123  | Outdoor Scuba Diving  | `outdoorScubaDiving`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.outdoorScubaDiving`  |
| 124  | Spectator Sports General  | `spectatorSportsGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsGeneral`  |
| 125  | Spectator Sports Baseball  | `spectatorSportsBaseball`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsBaseball`  |
| 126  | Spectator Sports Basketball  | `spectatorSportsBasketball`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsBasketball`  |
| 127  | Spectator Sports Football  | `spectatorSportsFootball`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsFootball`  |
| 128  | Spectator Sports Hockey  | `spectatorSportsHockey`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsHockey`  |
| 129  | Spectator Sports Racing  | `spectatorSportsRacing`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsRacing`  |
| 130  | Spectator Sports Soccer  | `spectatorSportsSoccer`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsSoccer`  |
| 131  | Spectator Sports TV Sports  | `spectatorSportsTvSports`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorSportsTvSports`  |
| 132  | Spectator NASCAR  | `spectatorNascar`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.spectatorNascar`  |
| 133  | Smoking Tobacco  | `smokingTobacco`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.smokingTobacco`  |
| 134  | Sports Grouping  | `sportsGrouping`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsGrouping`  |
| 135  | Sports Equestrian  | `sportsEquestrian`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsEquestrian`  |
| 136  | Sports Golf  | `sportsGolf`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsGolf`  |
| 137  | Sports Motorcycling  | `sportsMotorcycling`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsMotorcycling`  |
| 138  | Sports Skiing  | `sportsSkiing`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsSkiing`  |
| 139  | Sports Tennis  | `sportsTennis`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsTennis`  |
| 140  | Sports Leisure  | `sportsLeisure`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsLeisure`  |
| 141  | Travel Cruises  | `travelCruises`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.travelCruises`  |
| 142  | Travel Domestic  | `travelDomestic`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.travelDomestic`  |
| 143  | Travel International  | `travelInternational`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.travelInternational`  |
| 144  | Travel RV  | `travelRv`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.travelRv`  |
| 145  | Science Space  | `scienceSpace`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.scienceSpace`  |
| 146  | Woodworking  | `woodworking`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.woodworking`  |
| 147  | Buyer Books  | `buyerBooks`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerBooks`  |
| 148  | Buyer Crafts Hobbies  | `buyerCraftsHobbies`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerCraftsHobbies`  |
| 149  | Buyer Gardening Farming  | `buyerGardeningFarming`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerGardeningFarming`  |
| 150  | Buyer Jewelry  | `buyerJewelry`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerJewelry`  |
| 151  | Buyer Luggage  | `buyerLuggage`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerLuggage`  |
| 152  | Buyer Online  | `buyerOnline`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerOnline`  |
| 153  | Buyer Membership Club  | `buyerMembershipClub`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerMembershipClub`  |
| 154  | Buyer Health Beauty  | `buyerHealthBeauty`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerHealthBeauty`  |
| 155  | Buyer Children's Babycare  | `buyerChildrensBabycare`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerChildrensBabycare`  |
| 156  | Buyer Children's Learning Toys  | `buyerChildrensLearningToys`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerChildrensLearningToys`  |
| 157  | Buyer Children's Back To School  | `buyerChildrensBackToSchool`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.buyerChildrensBackToSchool`  |
| 158  | Apparel Children's  | `apparelChildrens`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelChildrens`  |
| 159  | Apparel Infant Toddlers  | `apparelInfantToddlers`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelInfantToddlers`  |
| 160  | Apparel Women's  | `apparelWomens`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelWomens`  |
| 161  | Apparel Women's Petite  | `apparelWomensPetite`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelWomensPetite`  |
| 162  | Apparel Women's Plus Size  | `apparelWomensPlusSize`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelWomensPlusSize`  |
| 163  | Apparel Women's Young  | `apparelWomensYoung`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelWomensYoung`  |
| 164  | Apparel Men's  | `apparelMens`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelMens`  |
| 165  | Apparel Men's Big Tall  | `apparelMensBigTall`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelMensBigTall`  |
| 166  | Apparel Men's Young  | `apparelMensYoung`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.apparelMensYoung`  |
| 167  | Auto Parts Accessories  | `autoPartsAccessories`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.autoPartsAccessories`  |
| 168  | Military Memorabilia Weapons  | `militaryMemorabiliaWeapons`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.militaryMemorabiliaWeapons`  |
| 169  | Musical Instruments  | `musicalInstruments`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.musicalInstruments`  |
| 170  | Photography Video Equipment  | `photographyVideoEquipment`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.photographyVideoEquipment`  |
| 171  | Sports Leisure (buyer)  | `sportsLeisureBuyer`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.sportsLeisure`  |
| 172  | Value Hunter  | `valueHunter`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.valueHunter`  |
| 173  | Reading General  | `readingGeneral`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.readingGeneral`  |
| 174  | Reading Audio Books  | `readingAudioBooks`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.readingAudioBooks`  |
| 175  | Reading Magazines  | `readingMagazines`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.readingMagazines`  |
| 176  | Reading Religious Inspirational  | `readingReligiousInspirational`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.readingReligiousInspirational`  |
| 177  | Reading Science Fiction  | `readingScienceFiction`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.readingScienceFiction`  |
| 178  | Reading Financial Newsletter Subscribers  | `readingFinancialNewsletterSubscribers`  | BOOLEAN  | B  | `owners.consumers.interestAttributes.readingFinancialNewsletterSubscribers`  |

---

## Employment Triggers

> **Date dependency:** `owners.employment.startDate` and `owners.businesses.modifiedDate` may be used as signals for "Recently Changed Jobs" etc.
>
> **Grain:** All employment triggers are in the **Employment source table (E)** — keyed on `employment_id` (separate ID space). Linked to owners via the employment matching process. Confirmed by `employment_data_triggers.sql` which joins on `o.ownerId = m.owner_id`.

| # | Enrichment Trigger | Enrichment Field | Type | Grain | Source Field(s) | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1  | Employment Match Confidence  | `employmentMatchConfidence`  | FLOAT  | E  | **EXTERNAL**  | From employment data provider  |
| 2  | Employment Data Last Updated Date  | `employmentDataLastUpdatedDate`  | DATE  | E  | **EXTERNAL**  | From employment data provider  |
| 3  | Career Match Confidence  | `careerMatchConfidence`  | FLOAT  | E  | **EXTERNAL**  | From employment data provider  |
| 4  | Career Data Last Updated Date  | `careerDataLastUpdatedDate`  | DATE  | E  | **EXTERNAL**  | From employment data provider  |
| 5  | LinkedIn URL  | `linkedinUrl`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 6  | Job Title  | `jobTitle`  | STRING  | E  | `owners.employment.title`  | Partial; enrichment adds external data  |
| 7  | Job Level  | `jobLevel`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 8  | Job Function  | `jobFunction`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 9  | Job Start Date  | `jobStartDate`  | DATE  | E  | `owners.employment.startDate`  |  |
| 10  | Recently Changed Jobs Since Last Update  | `recentlyChangedJobsSinceLastUpdate`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 11  | Recently Changed Jobs  | `recentlyChangedJobs`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 12  | Recently Promoted  | `recentlyPromoted`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 13  | Recently Retired  | `recentlyRetired`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 14  | Recently Changed Companies  | `recentlyChangedCompanies`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 15  | Possibly Student  | `possiblyStudent`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 16  | Possibly Unemployed  | `possiblyUnemployed`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 17  | Possible Additional Jobs  | `possibleAdditionalJobs`  | BOOLEAN  | E  | **EXTERNAL**  | From employment data provider  |
| 18  | Company Name  | `companyName`  | STRING  | E  | `owners.businesses.name`, `owners.employment.organization`  | Partial; enrichment adds external  |
| 19  | Company Domain  | `companyDomain`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 20  | Company Phone Number  | `companyPhoneNumber`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 21  | Company Address Line One  | `companyAddressLine1`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 22  | Company Address Line Two  | `companyAddressLine2`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 23  | Company City  | `companyCity`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 24  | Company State  | `companyState`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 25  | Company Zip  | `companyZip`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 26  | Company NAICS Code  | `companyNaicsCode`  | STRING  | E  | `owners.businesses.naics`  | Partial; enrichment adds external  |
| 27  | Company Industry  | `companyIndustry`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 28  | Company Revenue Range  | `companyRevenueRange`  | STRING  | E  | `owners.businesses.revenue`  | Partial; enrichment adds external  |
| 29  | Company Category  | `companyCategory`  | STRING  | E  | **EXTERNAL**  | From employment data provider  |
| 30  | Company Size Range  | `companySizeRange`  | STRING  | E  | `owners.businesses.numberOfEmployees`  | Partial; enrichment adds external  |
| 31  | Career Intelligence Last Updated  | `careerIntelligenceLastUpdated`  | DATE  | E  | **EXTERNAL**  | From employment data provider  |

---

## Source Fields NOT Used by Enrichment

These fields exist in the household build (`people.all`) but are **not carried into either the enrichment source table or the employment source table**.

> Note: `owners.employment` and `owners.businesses` ARE used — the relevant subfields (e.g., `title`, `startDate`, `name`, `naics`, `revenue`, `numberOfEmployees`) feed the **employment source table**. They appear in the list below as "full array not needed" because we don't carry the entire nested array — only the derived/selected fields go into the employment table.

### Top-Level Fields

| Source Field | Type | Why Excluded |
| --- | --- | --- |
| `primaryPropertyId`  | INTEGER  | Internal property linking  |
| `primaryPropertyForWindfallId`  | INTEGER  | Internal Windfall ID linking  |
| `lastSaleDateForWindfallId`  | DATE  | Internal Windfall ID linking  |
| `largePropertyCluster`  | BOOLEAN  | Internal clustering flag  |
| `address`  | STRING  | Matching only, not enrichment output  |
| `city`  | STRING  | Matching only  |
| `state`  | STRING  | Matching only  |
| `zipcode`  | STRING  | Matching only  |
| `zip4`  | STRING  | Matching only  |
| `county`  | STRING  | Matching only  |
| `countyFIPS`  | STRING  | Matching only  |
| `censusPlaceFIPS`  | STRING  | Matching only  |
| `metroName`  | STRING  | Matching only  |
| `fullName`  | STRING  | Matching only  |
| `firstName`  | STRING  | Matching only  |
| `middleName`  | STRING  | Matching only  |
| `lastName`  | STRING  | Matching only  |
| `nameSuffix`  | STRING  | Matching only  |
| `netWorthModel`  | STRING  | Internal model identifier  |
| `overrideDate`  | STRING  | Internal override  |
| `addressSelectionMethod`  | STRING  | Internal method flag  |
| `isTrainingData`  | BOOLEAN  | ML training flag  |
| `netWorthOverrideDate`  | STRING  | Internal override  |
| `isSplitHousehold`  | BOOLEAN  | Internal household flag  |
| `splitHouseholdLinkingId`  | STRING  | Internal linking  |
| `optOutApplied`  | BOOLEAN  | Privacy opt-out  |
| `originalId`  | STRING  | Original record ID  |
| `isCommercialPropertyOwner`  | BOOLEAN  | Not an enrichment trigger  |
| `isFarmlandOwner`  | BOOLEAN  | Not an enrichment trigger  |

### Owner Sub-Fields (Not Needed)

| Source Field | Type | Why Excluded |
| --- | --- | --- |
| `owners.ownerId`  | STRING  | Internal ID  |
| `owners.dbUsaIndividualId`  | STRING  | DBUSA linking  |
| `owners.dbUsaHouseholdId`  | STRING  | DBUSA linking  |
| `owners.fullName/firstName/middleName/lastName/nameSuffix`  | STRING  | Matching only  |
| `owners.ownerType`  | STRING  | Internal classification  |
| `owners.type`  | STRING  | Internal type  |
| `owners.ownerRelationship`  | STRING  | Internal classification  |
| `owners.assessorRelated`  | BOOLEAN  | Internal linking flag  |
| `owners.assessorLinkMethod`  | STRING  | Internal linking  |
| `owners.sources`  | STRING\[\]  | Data provenance only  |
| `owners.emails`  | RECORD\[\]  | Contact info, not enrichment trigger  |
| `owners.phoneNumbers`  | RECORD\[\]  | Contact info, not enrichment trigger  |
| `owners.birthDates`  | RECORD\[\]  | Used for age derivation (age is the enrichment field)  |
| `owners.secTransactions`  | RECORD\[\]  | Full list not needed; `recentSecTransactionAcquired/Disposed` are the derived dates  |
| `owners.donations`  | RECORD\[\]  | Full list not needed; derived dates/amounts are the enrichment fields  |
| `owners.coopSources`  | RECORD\[\]  | Data provenance only  |
| `owners.interests`  | RECORD\[\]  | Redundant with interestAttributes  |
| `owners.aliases`  | RECORD\[\]  | Matching only  |
| `owners.primarySource`  | STRING  | Data provenance only  |
| `owners.dmResponses`  | RECORD\[\]  | Full list not needed; `isDirectMailResponder` is the enrichment field  |
| `owners.charities`  | RECORD\[\]  | Full list not needed; derived dates/flags are the enrichment fields  |
| `owners.businesses`  | RECORD\[\]  | Full list not needed; `isSmallBusinessOwner` + employment enrichment fields cover it  |
| `owners.employment`  | RECORD\[\]  | Full list not needed; employment enrichment fields cover it  |
| `owners.sportsLicenses`  | RECORD\[\]  | Full list not needed; `hasBoat*License` booleans are the enrichment fields  |
| `owners.faaCertifications`  | RECORD\[\]  | Full list not needed; `hasPilotLicense` is the enrichment field  |

### Consumer Sub-Fields (Not Needed)

| Source Field | Type | Why Excluded |
| --- | --- | --- |
| `owners.consumers.dbusaHouseholdId`  | STRING  | DBUSA linking  |
| `owners.consumers.dbusaIndividualId`  | STRING  | DBUSA linking  |
| `owners.consumers.emails`  | STRING\[\]  | Contact info  |
| `owners.consumers.phones`  | STRING\[\]  | Contact info  |
| `owners.consumers.dateOfBirthYear/Month/Day`  | INTEGER  | DOB components — `age` is the enrichment field  |
| `owners.consumers.fipsCode`  | STRING  | Geographic code  |
| `owners.consumers.individualAttributes.ethnicCode`  | STRING  | Demographic, not a trigger  |
| `owners.consumers.individualAttributes.ethnicGroup`  | STRING  | Demographic  |
| `owners.consumers.individualAttributes.religiousAffiliation`  | STRING  | Demographic  |
| `owners.consumers.individualAttributes.languagePreference`  | STRING  | Demographic  |
| `owners.consumers.individualAttributes.hispanicCountryOfOrigin`  | STRING  | Demographic  |
| `owners.consumers.individualAttributes.assimilationCode`  | STRING  | Demographic  |
| `owners.consumers.individualAttributes.politicalIdeology`  | STRING  | Political modeling  |
| `owners.consumers.individualAttributes.voterId`  | STRING  | Voter registration  |
| `owners.consumers.individualAttributes.veteranIndividual`  | BOOLEAN  | Individual veteran (household-level is the trigger)  |
| `owners.consumers.householdAttributes.homeOwnerRenter`  | STRING  | Not a trigger  |
| `owners.consumers.householdAttributes.householdRank`  | INTEGER  | Internal ranking  |
| `owners.consumers.householdAttributes.singleParent`  | BOOLEAN  | Not a trigger  |
| `owners.consumers.householdAttributes.childNearHighSchoolGraduation`  | BOOLEAN  | Not a trigger  |
| `owners.consumers.householdAttributes.businessOwner`  | STRING  | Covered by `isSmallBusinessOwner`  |
| `owners.consumers.householdAttributes.soho`  | BOOLEAN  | Not a trigger  |
| `owners.consumers.householdAttributes.mailOrderDonor`  | BOOLEAN  | Not a trigger  |
| `owners.consumers.householdAttributes.tvSatelliteDish`  | BOOLEAN  | Not a trigger  |
| `owners.consumers.householdAttributes.boatOwner`  | BOOLEAN  | Covered by top-level `isBoatOwner`  |
| `owners.consumers.householdAttributes.recentlyMovedFlag`  | BOOLEAN  | FLAG (skip) — `recentMoveDate` is the enrichment field  |
| `owners.consumers.householdAttributes.recentDivorce`  | BOOLEAN  | FLAG (skip) — `recentDivorceDate` is the enrichment field  |
| `owners.consumers.householdAttributes.autoBuyNew/Used/*`  | INTEGER  | Auto purchase propensity, not a trigger  |
| `owners.consumers.financialAttributes.*` (most)  | various  | Used for derived triggers, not direct enrichment fields  |
| `owners.consumers.propertyAttributes.*` (home value fields)  | various  | Used for derived triggers  |
| `owners.consumers.mortgageAttributes.*`  | various  | Used for derived triggers  |

### Property Sub-Fields (Not Needed)

| Source Field | Type | Why Excluded |
| --- | --- | --- |
| `properties.id`  | INTEGER  | Internal ID  |
| `properties.address/city/state/zipcode`  | STRING  | Address components — matching only  |
| `properties.zip4`  | STRING  | Address detail  |
| `properties.county/countyFIPS/censusPlaceFIPS`  | STRING  | Geographic codes  |
| `properties.houseNumber/streetName/direction/addressSuffix/postDirection/unitPrefix/unitValue`  | STRING  | Parsed address  |
| `properties.metroName/metroDivisionName`  | STRING  | Metro area  |
| `properties.ownerIsTrust/ownerIsCorporateTrust`  | BOOLEAN  | Feeds `hasTrust` enrichment field  |
| `properties.calculatedEstimatedValue`  | INTEGER  | Alternate valuation  |
| `properties.valuationReason`  | STRING  | Internal  |
| `properties.inferredLastSaleAmount`  | INTEGER  | Internal inference  |
| `properties.inferredDownPayment`  | INTEGER  | Internal inference  |
| `properties.totalHomeEquityLineOfCredit`  | INTEGER  | Detail  |
| `properties.numPropertiesInTransaction`  | INTEGER  | Transaction detail  |
| `properties.vestaAvmAssessorEstimate/vestaAvmAttributeEstimate`  | FLOAT  | AVM sub-estimates  |
| `properties.totalOpenLoans`  | INTEGER  | Loan count  |
| `properties.loanAdjustmentReason`  | STRING  | Internal  |
| `properties.mortgageDetails`  | RECORD\[\]  | Full list not needed; `recentMortgageDate` is the enrichment field  |
| `properties.companyName`  | STRING  | Company owner name  |
| `properties.source`  | STRING  | Data provenance  |
| `properties.isTaxAddress`  | BOOLEAN  | Internal flag  |
| `properties.boats`  | RECORD\[\]  | Full list not needed; derived enrichment fields cover it  |
| `properties.planes`  | RECORD\[\]  | Full list not needed; `isPlaneOwner` is the enrichment field  |
| `properties.cars`  | RECORD\[\]  | Full list not needed; `primaryCarMake/Model` + derived fields cover it  |
| `properties.externalProperties`  | RECORD\[\]  | External linking  |
| `properties.taxAddressKey`  | STRING  | Internal key  |

### Other Top-Level Fields (Used Indirectly, Not Enrichment Fields)

| Source Field | Type | Used By |
| --- | --- | --- |
| `id`  | STRING  | Record identifier — needed for joins but not an enrichment trigger  |
| `netWorth`  | INTEGER  | Input to: `isAccreditedInvestor`, `isMidMarket*`, `percentNetWorthInSfrs`  |
| `calculatedNetWorth`  | INTEGER  | Input to derived triggers  |
| `models`  | RECORD\[\]  | Net worth model variants — internal  |
| `recentSecTransactionAcquired`  | DATE  | Input to `moneyInMotionAmount` — already a derived date, not a list  |
| `recentSecTransactionDisposed`  | DATE  | Input to `moneyInMotionAmount` — already a derived date, not a list  |
| `isCharityOfficer`  | BOOLEAN  | Related to Foundation Officer but separate from the trigger  |
| `hasCharityOfficer`  | BOOLEAN  | Related to Foundation Officer but separate from the trigger  |

---

## Open Questions

These are ambiguities and decisions that need input before the extraction is production-ready. Owners are noted where known.

### Owner / Consumer Selection

1. **Which owner is "primary"?** We currently filter on `owners.type = 'PRIMARY'` with fallback to first. Are there cases where multiple owners have `type = 'PRIMARY'`? If so, which one wins? Note: `owners.sql` uses `ROW_NUMBER() OVER (PARTITION BY ownerId ORDER BY ownerType NULLS LAST, gender NULLS LAST)` as a tiebreaker — should we replicate this?
2. **Which consumer record to use?** Each owner can have multiple `consumers[]` entries. We currently take the first one. Should it be the one with the matching `dbusaIndividualId`? The one with the most populated fields? Is there a ranking or primary flag?
3. **Occupation source preference** — we currently COALESCE `consumers.occupation` then `individualAttributes.occupationIndividual`. Are these ever both populated with different values? Which is more granular/reliable?

### Boat Fields

4. **Which boat's details do we use?** We currently pick the "primary boat" (`primaryBoat = TRUE`), falling back to the first boat in the array. Is `primaryBoat` always set? If there are multiple boats across multiple properties, do we always want the primary, or the largest, or the most recently seen?
5. `boatCompanyName` — what is this? The enrichment trigger says "Boat Company Name". The source has `boats.nameOfVessel` and `boats.manufacturerCode`. Is this the vessel name, the manufacturer name, or something else?
6. `boatClass` — is this the class of the primary boat or the "best" class? If someone owns a 20ft and a 50ft boat, which class do we report?
7. `boatAgeYears` / `boatYearsSinceLastSeen` — which boat? Same question — primary, newest, oldest?
8. **Has Boat Access — what constitutes "access"?** We currently define it as `isBoatOwner = TRUE OR any sports license exists`. Is that the intended definition, or does it include other signals (e.g., proximity to marina, boat club membership)?
9. **Has Boat Lift — where does this data come from?** It's marked DERIVED/EXTERNAL with no source field. Is it available from any provider, or should we drop it?

### Property Fields

10. **Property-level enrichment fields — always from primary property?** Fields like `propertyType`, `yearBuilt`, `bedroomCount`, `taxAssessedValue`, etc. are pulled from the primary property. Is that correct for all of them, or do some (like `taxAssessedValue`) need aggregation across all properties?
11. `lotSizeSqFt` comes from consumer data, `buildingSizeSqFt` from property data. Are these guaranteed to refer to the same property? Could they be out of sync?
12. `buildingToLotRatio` — is this the primary property only, or across all properties?
13. **SFR property type filter — what** `propertyType` values count as SFR? We currently use `LIKE '%SFR%' OR LIKE '%SINGLE%'`. What are the actual distinct values in the data?
14. **MFR unit thresholds — is** `units` always populated? If `units` is NULL for a property, should it be treated as 1 (SFR) or excluded?
15. **Primary Address Incorrect — where does this come from?** Marked EXTERNAL. Is this a SmartyStreets validation result? Is it populated in a separate enrichment step?

### Donation / Philanthropic Fields

16. **How do we distinguish philanthropic from political donations?** We currently use `source = 'FEC'` for political and everything else for philanthropic. Is that correct? Are there other political sources (e.g., state-level filings)?
17. **Top Donor "Prior Calendar Year" — relative to what?** Is it always relative to today's date, or relative to the data snapshot date?
18. **Top Donor threshold of 10,000 — is this a minimum to qualify, or a different kind of threshold?** The enrichment field stores the amount; does downstream check `>= 10000`?
19. `nteeCodes` and `regionalFocuses` — already filtered by 120mo threshold? These are pre-aggregated arrays on the source table. Are they already filtered by the donation date threshold, or do we need to recompute them from `owners.donations` with a date filter?

### Date Parsing

20. **What date formats exist in STRING date fields?** Fields like `recentDivorceDate`, `recentDeathDate`, `recentPurchaseDate`, `foundationOwnershipDate` are STRING. Are they always `YYYY-MM-DD`? Are there `YYYYMMDD`, `YYYY-MM`, or other formats?
21. `recentMoveDate` — which date source is authoritative? We have `recentPurchaseDate` (top-level STRING) and `recentlyMovedYear` + `recentlyMovedMonth` (from consumer household attributes). Which is more reliable? Can they conflict?

### Derived / Complex Fields

22. **Money in Motion — what is the computation?** Currently a placeholder. What signals go in? Is it the sum of SEC transaction values + property sales + mortgage amounts within the past year? Is there a specific formula?
23. **Liquidity Trigger / Windfall Trigger — what defines these?** Both are DERIVED placeholders. What are the actual business rules?
24. **Investable Assets / Liquid Net Worth — how are these computed?** Are these model outputs or formula-based (e.g., net worth minus illiquid real estate)?
25. **Accredited Investor — is $1M net worth the only criterion?** SEC rules also allow qualification via $200k individual income ($300k joint) for 2 consecutive years. Should `householdIncome` factor in?
26. **Match Confidence — is this populated post-matching only?** Should we include it in the enrichment source table, or is it added later in a different pipeline step?

### Employment Fields

27. **Which employment record is "current"?** We take the first `owners.employment[]` entry. Should it be the one with the most recent `startDate`? The one with no `endDate`?
28. **Company Name — businesses vs employment?** We COALESCE `owners.businesses.name` then `owners.employment.organization`. Which is the preferred source? Can `businesses` contain historical/closed businesses?
29. **Company Revenue / Size — STRING or numeric enrichment field?** The source has `revenue` as INTEGER and `numberOfEmployees` as INTEGER, but the enrichment trigger says "range". Should we bucket these into ranges, or pass the raw number?

### Miscellaneous

30. **Direct Mail Responder — any recency filter?** We flag as TRUE if any `dmResponses` exist. Should there be a time window (e.g., last 24 months)?
31. **Dwelling Type with multiple consumers — which one wins?** If two consumers in the same household report different `dwellingType` values, which is authoritative? (Grain: H requires a single household answer.)
32. **How many owners per household on average?** Affects the size of the denormalized enrichment source table since household data is duplicated per owner.

---
