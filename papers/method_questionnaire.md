# Methodology of the questionnaire's conjoint analysis

## Consistent scenarios

### Six underlying parameters
- Decarbonization: Slow; Intermediary; Fast (corresponding to IEA's CPS, STEPS, NZE)
- Working hours: baseline 40h, 25h (-37.5%), 30h (-25%); 35h (-12.5%); 45h (+12.5%)
- National redistribution: current; SN
- Global redistribution: current; GIT
- Public services: stable; increased
- Beef and flights: none; -60% beef; half flights; half both
Each attribute is uniformly drawn, leading to 5*2*2*3*2*4=480 cases, and 480^2=230k pairs.

### Seven displayed features:
- Temperature
- Own income
- Working hours
- National incomes
- Global incomes
- Public services
- Beef and flights
The order of features is randomized.

### How parameters define the scenario
Global 2100 GDP pc is defined using working hours and global redistribution:
     GIT   no-GIT
(25h 30    25)
30h: 45?   37.5
35h: 60    50
40h: 79    66
45h: 120   100
Note that 40h is current norm in IT where 15-64 employed work 1672h/year (paid work).
In SC, hours converge to 1000h/yr in 2100 and are ~(35/40)*1672 in 2035, vs. 2000h in PC/PI (where they are ~41h in 2035; in SC-45k/30k/15k they are 31/29/28 in 2035).
Note that hours pc decrease only from 630 to 480 in SC (960 in PC/PI) due to increasing employment (converging from 60% (incl. 68% for men) to 80% for both genders).

The base scenario is defined using working hours and global redistribution:
     GIT     no global redistr
25h: SC-30k       SI-30k
30h: SC-45k       SI-45k
35h: SC           SI
40h: MC           MI  
45h: PC           PI
Global redistribution activates Convergence; otherwise it's Inequality
Public services: version 2 if increased; 1 otherwise
Decarbonization: Slow: SD; Intermediary: ID; Fast: FD
Hence there are 5*2*2*3=30 scenarios

TODO remove PI2 scenarios from the .csv since they don't  model sectoral change

### How parameters determine incomes
SC/PC imply hourly productivity growth of .085%/year for IT over 2025-2100 (66 -> 125€/h)

The income distribution depends on hours, global redistribution and national redistribution. We use C under both redistributions, I under none, N if only national, G if only global. Hence there are 5*4=20 income distributions.
When they exist, we use Bothe distributions. Otherwise:
Define GR = country dividend - GIT (in SC2)
PI = current income ⋅ national growth PI
SN = SC - GR
SI = 0.5⋅PI (in 2100, another factor in 2035)
SG = SI + GR

Then other distributions are defined as a coef times the reference S case, e.g.:
SI-30k = .5⋅SI, SN-30k = .5⋅SN, SG-30k = .5⋅SG, SC-30k = .5⋅SC
2100 coefs are as follows: S30k: .5, S45k: .75, M: 630/480 (keeping hours pc constant), P: 2
From them, we easily recover the 2100 GDP of each scenario.
2035 coefs are TODO

Then a decarbonization factor is applied to 2035 incomes: 1 for SD, .98 for ID, .96 for FD.

Finally, a public services tax is added to 2035 incomes of *scope* I, G if public services = increased; and subtracted to 2035 incomes of scope N, C if public services = stable.


### How parameters affect temperature
For scenarios that are either 1=(public services stable & no beef nor flight reduction) or 2=(public services increased & both beef and flights reduction) and that are not of *hours* M, we use the value given by Chancel in chancel_temp2100_completed.csv for the 2100 temperature.
Otherwise, we use 2100 GDP, decarbonization, public services, beef/flights to estimate it: 
- if decarbonization = SD or ID, we fix the change in function of public services (stable: 1, increased: 2) since material vs. immaterial sectors matter in this case
- if decarbonization = FD, we fix the change in function of beef (no beef reduction: 1, beef reduction: 2) since land-use effects dominate in this case

Then, if change is fixed to 1:
- subtract .24°C in case of beef reduction
- subtract .155°C in case of flights reduction
- subtract .0004875⋅(67.25+2.06*GDPpc2100/1000)°C in case of increased public services (estimated as change in fossil between 1 and 2, potentially varying with hours)
if change is fixed to 2:
- add .24°C in case of no beef reduction
- add .155°C in case of no flights reduction
- add .0004875⋅(67.25+2.06*GDPpc2100/1000)°C in case of increased public services

Chanceletal2026Appendix_Emission_Output reports cumulative emissions of almost all scenarios and 2100 temperature of most scenarios, where a scenario is defined by the combination of type (SC, PI, PC, SC-45k, SC-30k, SC-15k), structural change (1 if not, 2 if yes) and decarbonization pace (FD, ID, SD). E.g. sheet SC2_FD reports emissions and temperature of the benchmark scenario.
When Chancel doesn't report the temperature, we predict it using cumulative emissions, their square, the type, decarbonization pace, structural change indicator, and the interaction between cumulative emissions and structural change, from a model estimated on complete data. The model always accurately predicts the temperature rounded at a tenth of a Celsius degree. 



Best model (highest adjusted-R² = .9999; max_diff_round=0):
T ~ emissions*sectoral_change + emissions² *decarb + type + type:decarb:sectoral_change
Great model (adjusted-R² = .9989; max_diff_round=0):
T ~ emissions*sectoral_change + emissions² + type + decarb
Great model (adjusted-R² = .9996; max_diff_round=0):
T ~ emissions * sectoral_change * type + emissions² * type + decarb
adj‑R² 0.999, max_diff_round = 0:
T ~ emissions + emissions:sectoral_change + emissions:gdp + decarb:sectoral_change

Best model without emissions (adj-R²= .9978, max_diff=0.10): 
T ~ type:decarb + decarb:sectoral_change 
Great model without emissions (adjusted-R² = .9978; max_diff_round=0): 
T ~ type * decarb + decarb:sectoral_change
Great model without emissions (adjusted-R² = .9978; max_diff_round=0): 
T ~  type:decarb + type:sectoral_change + decarb:sectoral_change
adj‑R² 0.989, max_diff = 0.10:
T ~ I(gdp²) + sectoral_change + gdp:decarb

T ~ 1.227 + .0004875⋅emissions

Missing temperatures: SC1_SD, PC2_ID, PC2_SD, PI1_ID, PI2_FD, PI2_SD

Based on 2035 GDP figures and assuming SC variants only differ by working hours (and have same productivity), I get:
SC-45k: 31h, SC-30k: 29h, SC-15k: 28h

TODO: remove SC growth from 2035 scenarios given that it's already baked in the respondent's expected income
- Working hours => GDP: baseline 40h, 30h (-25%); 35h (-12.5%); 45h (+12.5%)
- National distribution: current; SN
- Global distribution: current; GIT
- Decarbonization: Slow and -0% inc; Inter and -2% inc; Fast and -4% inc
- Structural change: tax health/educ and T-x°C; none
- Beef and flights: none; half beef and T-x°C; half flights and T-x°C; half both and T-x°C
4*2*2*3*2*4

Current ratio IT/World GDP = 2.45
2100 PI ratio: 2.03

- Decarbonization: Slow costs nothing; Inter 2% of each cash income; Fast 4% (PB: already counted in GIT)
- Working hours: GDP is proportional to working hours.


## Income distributions for the questionnaire

We use 4 types of income distributions:
- IT25: Italy 2025 to situate the respondent
- IT35: Italy 2035 to compute their own future income in a given scenario
- IT100: Italy 2100 to show the end level of within-country inequality
- World100: World 2100 to show the end level of between-country inequality
We use an income concept relevant to the respondents: cash income after direct taxes and monetary transfers (or "cash income" for short), gross of CFC (as in GDP and not NDP). 

We estimate the distributions in the SC scenario as follows:
- IT25: We first use Fisher-Post & Gethin data to recover cash income distributions. We use 2019 data and first define:
net cash income pre-GIT = pretax - all taxes + govt cash transfers - imputed rents and retained earnings
all taxes = tax_dir_pit + tax_dir_wea + tax_cit + tax_soc + tax_ind (PIT, wealth, CIT, social contrib, VAT)
We include tax_ind ~ VAT because pretax income is at market prices, so we need to subtract VAT from it to recover the NNI at factor prices (to which cash income sums).
Imputed rents and retained earnings are estimated at respectively 3.5% of housing capital and 50% of capital income, and the housing share of capital is assumed to increase with income along a housing_gradient calibrated using 2014 French data from Garbintini et al. (2021).
At this stage, we re-order the distribution since adding/subtracting terms to pretax sometimes makes it non-monotone. 
We then scale net cash income to 2025 NNI from Bothe et al. data and add depreciation (CFC times the capital share) to arrive at gross cash income pre-GIT.  
cash_income_2025 = (net cash income pre-GIT 2019 shares)*NNI_2025 + CFC

- IT35: For the shape of the distribution we use "full income", taken from Bothe as diinc (corresponding to national secondary income after taxes and all transfers, including in-kind public services and collective expenditures) which accounts for changes in inequality due to SC scenario, we subtract the global income tax and add country dividends modeled as a global equal cash transfer (given in Bothe sheet E3bp):
income = full income (diinc) - GIT + country dividend
To make results comparable with the cash income entered by the respondent, we rescale at each gpercentile:
grossIT35 = gross cash income 2035 = income 2035 * cash_income_2025/income_2025.
Finally, we subtract from this extra taxes needed to achieve the expansion of public spending between 2025 (20% of IT GNI) and 2035 (23%). 
IT35 = cash income 2035 = income 2035 * cash_income_2025/income_2025 * (1-income 2035 * cash_income_2025/income_2025).
- IT100, World100: While cash income makes sense at the individual level to understand the short-term change in one's purchasing power; "full income" inclusive of public services makes more sense to compare standards of living between countries and across time or scenarios (especially when they vastly differ in terms of public provision). Therefore, for 2100 we use full income - GIT + country dividends (both very small in 2100 and zero in 2025). But to make both IT100 and World100 comparable to IT25 and IT35, we re-scale them by the ratio of average cash income over average full income in 2025 IT. In other words we use:
rescaled income = (full income (diinc) - GIT + dividend)*avg_cash_income_2025_IT/avg_full_income_2025_IT (this ratio_IT=.69)

(We rescale by a constant ratio across gpercentiles because the shape that accurately reflects inequality is given by income; for IT35 on the contrary we want comparability with IT25 so we rescale by a percentile-specific ratio and use diinc, GIT and dividend for the shape change.) 
=>  check percentile-specific ratio is roughly constant
=> TODO report avg income & cash income 25/35/100 IT/World SC/PI/PC
=> graphs World, IT with all distributions we use

Other scenarios in IT100, World100:
Note that Bothe et al. give future distributions only for the SC scenario. This is how we proceed for other scenarios:
- PI: we assume that inequality does not change and simply rescale every country's distribution by the growth in GDP in PI scenario according to sheet A0pi of Chancel's Appendix. There is no GIT nor dividend in this scenario.
- For the other scenarios, we assume the same transfers as in SC in proportion of GDP, and simply rescale the country distributions by a given factor: PC=2, SC1=1, SC45k=0.75, SC30k=0.5, SC15k=0.25. 
To aggregate country distributions into the world one, we use higher population projections for PI and PC (UN medium, Chancel sheet Z0b) than for SC (Z0a).

Other scenarios in IT35:
- PI: we rescale IT25 by 1.4, an approximation of growth given by Chancel sheet A0pi. This is the only scenario for which we use the current level of inequality (for the other we use SC's shape).
- PC: we rescale grossIT35 by 1.15, an approximation of GDP in 2035 in PC over SC
- SC45k: we rescale IT35 by GDP_IT25/GDP_IT35 since 2025 GDP this roughly corresponds to the GDP in 2035 in scenario SC45k from sheet A0, and this makes it more easily interpretable. We also express the other two as a deviation from current GDP:
- SC30k: we rescale IT35 by 0.95*GDP_IT25/GDP_IT35
- SC15k: we rescale IT35 by 0.9*GDP_IT25/GDP_IT35

### Question wording

Say scenarios are consistent, recall Paris target and where current policies would bring us.