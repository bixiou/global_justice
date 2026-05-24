# Step-by-step guide — Global Justice Situator

## Context

I am Adrien Fabre, CNRS researcher at CIRED. This is a project to create a webpage simulating the user's income in a scenario with global policies towards sustainable convergence, based on Chancel et al. (2026) and Bothe et al. (2026), both part of the Global Justice Report. Check out CLAUDE.md for more context.
We are primarily interested in posttax post-GIT (Global Income Transfers), which we will refer to as "income" for short. 
We are primarily interested in the Sustainable Convergence scenario: unless otherwise specified, this is the scenario we consider ourselves in by default. 
When coding the webpage, prepare a workflow allowing me to test it locally (FYI, I use Windows 10 and have XAMPP installed). 

## Steps

- [x] Read all data files to understand the data structure and the project.
- [x] Read CLAUDE.md and TODO.md and ask me any clarification questions.
- [x] Create README.md and explain how the income distribution is coded in the data (with variable names, definitions, etc.). Choose in which coding language you will work.
- [x] Note that the list of countries/regions is: DE  DK	ES	FR	GB	IT	NL	NO	SE	OC	QM	US	CA	AU	NZ	OH	AR	BR	CL	CO	MX	OD	AE	DZ	EG	IR	MA	SA	TR	OE	CD	CI	ET	KE	ML	NE	NG	RW	SD	ZA	OJ	RU	OA	CN	JP	KR	TW	OB	BD	IN	ID	MM	PK	PH	TH	VN	OI, Europe,	North America/Oceania,	Latin America	Middle, East/North Africa,	Subsaharan Africa,	Russia/Central Asia,	East Asia	South & South-East Asia
- [x] Prepare data/income_pre_git.csv giving the posttax net income gpercentile 10, 50, 99, 99.9, 99.99 and 99.999 of each country and region for each year between 2020 and 2100: posttax net income thresholds and/or average, using tabs I2... and I5... of Botheetal2026AppendixDistribution.
- [~] Prepare data/income.csv giving, for each income gpercentile of each country: income for each year between 2020 and 2100. You will start from income_pre_git, then add to that Global Income Transfers resulting from the tax rates defined in the papers and income/wealth levels given in the data and assuming that they are distributed as a lump-sum equal cash transfer for each human, and compute the value of each gpercentile (to do this step, find out in the documentation/papers what method the authors use to recover all gpercentiles from the few ones present in their database.)
  NOTE: income.csv currently uses SC scenario I-series (I5 thresholds × I2i as anchors, log-interpolation for intermediate percentiles). This implicitly captures GIT at the country-average level (I2i is post-GIT). The explicit lump-sum distributional adjustment within each country has NOT yet been applied. Ask user for clarification.
- [x] Using a similar method for wealth, prepare data/wealth.csv giving, for each wealth gpercentile of each country: wealth at the start date (before any policy is implemented) for each year between 2020 and 2100.
- [x] Prepare data/income_world.csv giving, for each income gpercentile of the world distribution: income at the start date (before any policy is implemented) for each year between 2020 and 2100.
- [x] Prepare data/wealth_world.csv giving, for each wealth gpercentile of the world distribution: wealth at the start date (before any policy is implemented) for each year between 2020 and 2100.
- [x] Prepare a webpage of a situator where the user will see how their income evolves in the Sustainable Convergence scenario. The webpage asks the user for their country (dropdown list of the list of countries/regions), then automatically finds out the corresponding currency, asks the user for their annual income in their currency, converts it in euro internally using up-to-date conversion rate, and then shows two graphs: "evolution" which shows how their income will evolve over time (in their own currency) using income.csv (assuming their gpercentile and country are constant), and "distribution" which shows the world income distributions (with income in user's currency on the y-axis and "humans from the poorest to the richest" on the x-axis): the current one in red, the 2030 one in darkorange, 2035 one in orange, 2050 in light green, 2100 in dark green, showing on each of them the user's income using a big dot. 
- [] Save the user's IP, geolocation, language, country and income in a database.
- [] Prepare a dozen versions of the webpage: one for each major language. Automatically translate the webpage based on the user's language locale (using English by default if their language is not available).
- [] Prepare data/income_prime.csv giving, for each income gpercentile of each country: income prime at the start date (before any policy is implemented), in 2030, in 2035, in 2050, in 2080 and in 2100, where income prime is defined as income minus health and education expenditures.

## Done so far
