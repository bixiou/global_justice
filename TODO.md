# Step-by-step guide — Global Justice Situator

## Context

I am Adrien Fabre, CNRS researcher at CIRED. This is a project to create a webpage simulating the user's income in a scenario with global policies towards sustainable convergence, based on Chancel et al. (2026) and Bothe et al. (2026), both part of the Global Justice Report. Check out CLAUDE.md for more context.
We are primarily interested in posttax post-international transfers income, which we will refer to as "income" for short. 
We are primarily interested in the Sustainable Convergence scenario: unless otherwise specified, this is the scenario we consider ourselves in by default. 
When coding the webpage, prepare a workflow allowing me to test it locally (FYI, I use Windows 10 and have XAMPP installed). 

## Steps

- [] Read all data files to understand the data structure and the project.
- [] Read CLAUDE.md and TODO.md and ask me any clarification questions.
- [] Create README.md and explain how the income distribution is coded in the data (with variable names, definitions, etc.). Choose in which coding language you will work.
- [] Prepare data/income.csv giving, for each income gpercentile of each country: income at the start date (before any policy is implemented), in 2030, in 2035, in 2050, in 2080 and in 2100.
- [] Prepare data/wealth.csv giving, for each wealth gpercentile of each country: wealth at the start date (before any policy is implemented), in 2030, in 2035, in 2050, in 2080 and in 2100.
- [] Prepare data/income_world.csv giving, for each income gpercentile of the world distribution: income at the start date (before any policy is implemented), in 2030, in 2035, in 2050, in 2080 and in 2100.
- [] Prepare data/wealth_world.csv giving, for each wealth gpercentile of the world distribution: wealth at the start date (before any policy is implemented), in 2030, in 2035, in 2050, in 2080 and in 2100.
- [] Prepare a webpage of a situator where the user will see how their income evolves in the Sustainable Convergence scenario. The webpage asks the user for their country (dropdown list), then automatically finds out the corresponding currency, asks the user for their annual income in their currency, converts it in euro internally using up-to-date conversion rate, and then shows two graphs: "evolution" which shows how their income will evolve over time (in their own currency) using income.csv (assuming their gpercentile and country are constant), and "distribution" which shows the world income distributions (with income in user's currency on the y-axis and "humans from the poorest to the richest" on the x-axis): the current one in red, the 2030 one in darkorange, 2035 one in orange, 2050 in light green, 2100 in dark green, showing on each of them the user's income using a big dot. 
- [] Save the user's IP, geolocation, language, country and income in a database.
- [] Prepare a dozen versions of the webpage: one for each major language. Automatically translate the webpage based on the user's language locale (using English by default if their language is not available).
- [] Prepare data/income_prime.csv giving, for each income gpercentile of each country: income prime at the start date (before any policy is implemented), in 2030, in 2035, in 2050, in 2080 and in 2100, where income prime is defined as income minus health and education expenditures.

## Done so far
