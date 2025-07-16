/**
* Name: Leganés
* Author: Javier Santos Menéndez
*/

model Leganes

global {
    // Flag to render the simulation in 3D/2D
	bool render3D <- false;
	bool carsEnhancedAppearance <- true;
	bool showTextChargingPoints <- false;
	
	// Flag to enable vehicle-to-grid (V2G) energy feed from taxis
	bool V2GActivated <- false;
	
	// Agent counters in the simulation
	int contadorPeatones <- 0;
	int contadorCoches <- 0;
	int contadorTaxis <- 0;
	int contadorTrenes <- 0;
	
	// Number of people in the simulation
	int numPeople;
	
	// Total number of autonomous vehicles
	int numberOfElectricCars;
	
	// Search radius for start/end when no route is found
	float radiusDefault <- 1000.0;
	
	// Public transport configuration
	int numBuses;
	int numStops;
	int numBusRoutes;
	int busStationIndex;
	
	// Flag to show road directions
	bool watchDirections <- false;
	
	// Imported map files
	file shapefileRoads <- file("../includes/Maps/Leganes/ROADS.shp");
	file shapefileCrossroads <- file("../includes/Maps/Leganes/CROSSROADS.shp");
	file shapefileStreets <- file("../includes/Maps/Leganes/STREETS.shp");
	file buildingsShapefile <- file("../includes/Maps/Leganes/BUILDINGS.shp");
	file shapefileRailway <- file("../includes/Maps/Leganes/railway3.shp");
	
	// Simulation start date
	date starting_date <- date("2024-06-12 06:59:59");
	// Current simulation date
	date current_date;
	// Duration of each simulation step (in minutes)
	float step <- 3*0.016 #minutes; // minutes
	
	bool is_night;
	rgb background_color;
	int light_intensity;
	
	// Parameters for person generation
	int minWorkStart <- 6;
	int maxWorkStart <- 8;
	int minWorkEnd <- 16;
	int maxWorkEnd <- 20;
	float minSpeed <- 1.0  #km / #h; // km/h
	float maxSpeed <- 5.0 #km / #h;  // km/h
	
	// Road networks
	graph roadsNetwork;
	graph streetsNetwork;
	graph tracksNetwork;
	
	// Traffic control variables
	float lane_width <- 0.7;
	float closeDistance <- 0.75;
	float farDistance <- 4.5;
	
	// Simulation area definition
	geometry shape <- envelope(shapefileRoads) + 100.0;
	
	// Simulation statistical data
	string statisticsCity <- "28074 Leganés";
	string statisticsProvince <- "28 Madrid";
	string statisticsAutonomousCommunity <- "13 Madrid, Comunidad de";
	
	// Residential buildings and households
	list<building> residential_buildings;
	list<Household> households;
	
	// Transport usage probabilities
	float walkShortDistanceProbability   <- 0.34 + 0.34/(0.34+0.48+0.02)*0.16;
	float carShortDistanceProbability    <- 0.48 + 0.48/(0.34+0.48+0.02)*0.16;
	float taxiShortDistanceProbability   <- 0.02 + 0.02/(0.34+0.48+0.02)*0.16;
	
	float carLongDistanceProbability     <- 0.48 + 0.48/(0.48+0.16+0.02)*0.34;
	float trainLongDistanceProbability   <- 0.16 + 0.16/(0.48+0.16+0.02)*0.34;
	float taxiLongDistanceProbability    <- 0.02 + 0.02/(0.48+0.16+0.02)*0.34;
	
	// Vehicle consumption matrix
	list<map<string, string>> vehicleConsumptionMatrix;
	
	// Population generation statistics
	map<string, float> householdStructureProbabilities;
	map<string, float> householdStructureProbabilities1Person;
	map<string, float> householdStructureProbabilities2Persons;
	map<string, float> householdStructureProbabilities3Persons;
	map<string, float> householdStructureProbabilities4Persons;
	map<string, float> householdStructureProbabilities5Persons;
	map<string, float> motherAgeProbabilities;
	map<string, float> sexProbabilities;
	map<string, float> orientationProbabilities;
	map<string, float> ageGroupProbabilities;
	map<string, float> leganesEntryProbabilities;
	map<string, float> leganesExitProbabilities;
	map<string, float> districtDistributionProbabilities;
	map<string,map<string, float>> husbandAgeCoupleProbabilities;
	map<string,map<string, float>> wifeAgeCoupleProbabilities;
	
	// Age ranges and population count
	list<string> age_ranges <- [
	    "0-4", "5-9", "10-14", "15-19", "20-24", "25-29", "30-34", "35-39", "40-44",
	    "45-49", "50-54", "55-59", "60-64", "65-69", "70-74", "75-79", "80-84",
	    "85-89", "90-94", "95-99", "100-120"
	];
	list<int> age_counts <- [
	    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	];
	
	// CSV data
	list<string> dataCSV <- [];
	
	// CO2 emission calculation
	bool calculate_CO2 <- true;
	
	// Taxi call center
	taxiSwitchboard taxiCallCenter <- nil;
	    
	/*
	 * IIIIII  NN   NN  IIIIII  TTTTTTT
	 *   II    NNN  NN    II       T
	 *   II    NN N NN    II       T
	 *   II    NN  NNN    II       T
	 * IIIIII  NN   NN  IIIIII     T
	 */
	init { 
	    current_date <- starting_date;  // Current date initialized.
	    background_color <- rgb("gray");  // Background color set.
	    light_intensity <- 100;           // Light intensity defined.
	    
	    create databaseReader number: 1 {}  // Agent for reading the database.
	    
	    create roads from: shapefileRoads with: [
	        lanes::int(read("lanes")),               // Number of lanes.
	        num_lanes::int(read("lanes")),             // Duplicate number of lanes for reference.
	        maxspeed::int(read("maxspeed")) * 0.277778,  // Max speed converted from km/h to m/s.
	        oneway::string(read("oneway")),             // Indicates one-way status.
	        vehh::string(read('vehh'))
	    	] {
	        	geometryDisplayForMood3D <- shape + (2.5 * lanes);  // Adjusts geometry size for 3D display.
	    	}
	    
	    create crossroads from: shapefileCrossroads with: [
	        isTrafficLight::(read("highway") = "traffic_signals"),
	        isYield::(read("highway") = "give_way"),
	        isStop::(read("highway") = "stop"),
	        isZebraCrossing::(read("highway") = "crossing"),
	        isStreet::(read("highway") = "street" or read("highway") = 'crossingWalker'),
	        isBusStop::(read("highway") = "bus_stop"),
	        isTrainStation::(read("highway") = "train"),
	        nameTrainStation::(read("name")),
	        isChargingPoint::(read("highway") = "chargingStation"),
	        isTurningCircle::(read("highway") = "turning_circle"),
	        isCity::(read("highway") = "isCity"),
	        nameCity::(read("city")),
	        isCrossroad::(read("highway") = "crossroad"),
	        isMidPoint::(read("highway") = "roadMidPoint"),
	        typeCharge::"",
	        name::(read("name")),
	        subType::0
	    ] {
	        if isChargingPoint {
	            if (int(read("CCS2")) > 0) {
	                hasCCS2 <- true;
	                maxTension <- 500.0;       // Maximum voltage.
	                maxElectricity <- 125.0;   // Maximum current.
	                maxPower <- 50.0;          // Maximum power.
	                timeRecharge <- 0.5;       // Recharge time in hours.
	            }
	            if (int(read("Type2")) > 0) {
	                if (subType = 1) {
	                    maxElectricity <- 32.0;   // Maximum current for Type2 subtype 1.
	                    maxPower <- 21.0;         // Maximum power for Type2 subtype 1.
	                    timeRecharge <- 1.5;      // Recharge time in hours for Type2 subtype 1.
	                } else {
	                    hasType2 <- true;
	                    maxElectricity <- 63.0;   // Maximum current for Type2.
	                    maxPower <- 43.0;         // Maximum power for Type2.
	                    timeRecharge <- 0.75;     // Recharge time in hours for Type2.
	                }
	            }
	            if (int(read("ChaDeMo")) > 0) {
	                hasChaDeMo <- true;
	                maxElectricity <- 32.0;   // Maximum current for ChaDeMo.
	                maxPower <- 21.0;         // Maximum power for ChaDeMo.
	                timeRecharge <- 1.5;      // Recharge time in hours for ChaDeMo.
	            }
	        }
	    }
	    
	    create building from: buildingsShapefile with: [
	        buildingName::string(read('name')),
	        buildingType::string(read('building')),
	        leisureType::string(read('leisure')),
	        railwayType::string(read('railway')),
	        district::read("district"),              // Building district.
	        buildingHeight::rnd(20,30)                  // Building height in meters.
	    ] {
	        geom_display <- shape;
	        location <- geom_display.centroid;         // Location set as the centroid of the geometry.
	        write "Building ID: " + " Location: " + location + " Shape: " + shape + " Name: " + buildingName + " Type: " + buildingType;
	    }
	    
	    create streets from: shapefileStreets {}       // Agents for pedestrian streets.
	    create railway from: shapefileRailway {}        // Railway tracks.
	    
	    map generalSpeedMap <- roads as_map(each::(each.shape.perimeter / each.maxspeed));  // General speed map.
	    
	    list<crossroads> crossroadsRoadNetwork <- crossroads where (!each.isStreet);  // Nodes for the road network.
	    roadsNetwork <- (as_driving_graph(roads, crossroadsRoadNetwork)) with_weights generalSpeedMap;  // Road network graph.
	    
	    list<crossroads> crossroadsStreets <- crossroads where (each.isStreet or each.isZebraCrossing);  // Nodes for pedestrian streets.
	    map generalWalkerMap <- streets as_map(each::(each.shape.perimeter));  // Perimeter map for walkers.
	    streetsNetwork <- as_driving_graph(streets, crossroadsStreets) with_weights generalWalkerMap;  // Pedestrian network graph.
	    
	    list<crossroads> crossroadsRailway <- crossroads where (each.isTrainStation);  // Train station nodes.
	    tracksNetwork <- as_driving_graph(railway, crossroadsRailway);  // Railway network graph.
	    
	    ask crossroads { do initialize; }  // Initialize crossroads.
	    
	    create train number: 1 {
	        initialCrossroad <- one_of(crossroads where (each.isTrainStation and each.nameTrainStation = "Humanes"));  // Train's initial station.
	        targetCrossroads <- one_of(crossroads where (each.isTrainStation and each.nameTrainStation = "Madrid"));   // Train's target station.
	    }
	    
	    create taxiSwitchboard number: 1 returns: centralita;
	    taxiCallCenter <- centralita[0];  // Assign taxi call center.
	    
	    create electricCars number: numberOfElectricCars {
	        initialCrossroad <- one_of(crossroads where !(each.crossroadsNoInitialLocation));  // Initial intersection for electric cars.
	        self.location <- initialCrossroad.location;  // Electric car initial location.
	        targetCrossroads <- one_of(crossroads where !(each.crossroadsNoInitialLocation));  // Target intersection for electric car.
	        max_acceleration <- 5 / 3.6;               // Maximum acceleration.
	        max_speed <- 70.0;                       // Maximum speed in km/h.
	        proba_block_node <- 0.0;                 // Node block probability.
	        proba_lane_change_down <- 0.8 + (rnd(500) / 500);  // Down lane change probability.
	        proba_lane_change_up <- 0.5 + (rnd(500) / 500);      // Up lane change probability.
	        proba_respect_priorities <- 1.0 - rnd(200 / 1000);   // Probability to respect priorities.
	        proba_respect_stops <- [1.0];            // Stop respect probability.
	        proba_use_linked_road <- 0.0;            // Linked road usage probability.
	        right_side_driving <- true;              // Right-hand driving.
	        security_distance_coeff <- 5 / 9 * 3.6 * (1.5 - rnd(1000) / 1000);  // Safety distance coefficient.
	        speed_coeff <- 1.0 - (rnd(600) / 1000);  // Speed coefficient.
	        thresholdStucked <- float((1 + rnd(5)));   // Threshold for being stuck (in minutes).
	        vehicle_length <- rnd(2.5, 4.0);         // Vehicle length in meters.
	        probabilityBreakdown <- 0.00001;         // Breakdown probability.
	        carStopInAZebraCrossing <- false;        // Does not stop at zebra crossing.
	        carStopInAYield <- false;                // Does not stop at yield.
	        carStopInAStop <- false;                 // Does not stop at stop.
	        carStopInAElectricRecharge <- false;     // Does not stop for electric recharge.
	        soc <- rnd(0.2000, 0.8000);               // Initial battery state of charge.
	        list<string> types <- ["CCS2", "Type2", "ChaDeMo"];
	        typeConnector <- one_of(types);           // Assigned connector type.
    }
    
    ask electricCars { do initialize; }  // Initialize electric cars.
    
    residential_buildings <- building where (
        each.buildingType = "residential" or 
        each.buildingType = "apartments" or 
        each.buildingType = "house" or 
        each.buildingType = "semidetached_house" or 
        each.buildingType = "terrace" or 
        each.buildingType = "cabin" or 
        each.buildingType = "dormitory" or 
        each.buildingType = "detached" or 
        each.buildingType = "construction" or 
        each.buildingType = "yes"
    );  // Residential buildings (collect).
    
    // Number of each household type
    int numHouseholds <- createFamilies(0);
	int n1 <- length(households where (length(each.members) = 1));
	int n2 <- length(households where (length(each.members) = 2));
	int n3 <- length(households where (length(each.members) = 3));
	int n4 <- length(households where (length(each.members) = 4));
	int n5 <- length(households where (length(each.members) = 5));
	int totalHouseholds <- sum(n1, n2, n3, n4, n5);
	
	// Write out statistics for household composition (population generation)
	write("Percentage of single-person households: " 
	      + with_precision((n1 / totalHouseholds) * 100, 2) + " %");
	write("Percentage of two-person households: " 
	      + with_precision((n2 / totalHouseholds) * 100, 2) + " %");
	write("Percentage of three-person households: " 
	      + with_precision((n3 / totalHouseholds) * 100, 2) + " %");
	write("Percentage of four-person households: " 
	      + with_precision((n4 / totalHouseholds) * 100, 2) + " %");
	write("Percentage of five-person households: " 
	      + with_precision((n5 / totalHouseholds) * 100, 2) + " %");
	}
	
	reflex update_time {
	    // Increment current simulation date by step duration
	    current_date <- current_date + step;
	    // Determine whether it is night based on current hour
	    is_night <- (current_date.hour >= 22 or current_date.hour < 7);
	    if (is_night) {
	        // Set night-time background and lighting
	        background_color <- rgb("darkblue");
	        light_intensity <- 30;
	    } else {
	        // Set day-time background and lighting
	        background_color <- rgb("gray");
	        light_intensity <- 100;
	    }
	}

    /* 
    ███████  █████  ███    ███ ██ ██      ██ ██       █████  ██████   ██████  ██████  
	██      ██   ██ ████  ████ ██ ██      ██ ██      ██   ██ ██   ██ ██    ██ ██   ██ 
	█████   ███████ ██ ████ ██ ██ ██      ██ ██      ███████ ██████  ██    ██ ██████  
	██      ██   ██ ██  ██  ██ ██ ██      ██ ██      ██   ██ ██   ██ ██    ██ ██   ██ 
	██      ██   ██ ██      ██ ██ ███████ ██ ███████ ██   ██ ██   ██  ██████  ██   ██ 
    
    This module of the code defines the logic that generates the people in the simulation and their characteristics.
    */
    
    
	Person matchPartner(Person partner, Household household) {
	    // Select orientation using global probabilities
	    string orientation <- rnd_choice(orientationProbabilities);
	    string sex;
	    if (orientation = "heterosexual") {
	        // If the partner is "Male", assign "Female"; otherwise assign "Male"
	        sex <- (partner.gender = "Male") ? "Female" : "Male";
	    } else {
	        // For other orientations, assign the same gender as the partner
	        sex <- (partner.gender = "Male") ? "Male" : "Female";
	    }
	    // Determine age range for the partner
	    string partnerAgeRange <- partner.age_range;
	    if ((split_with(partnerAgeRange, "-")[0] as_int 10) >= 60) {
	        partnerAgeRange <- "60-99";
	    }
	    map<string, float> partnerProbabilities <- (partner.gender = "Male")
	        ? husbandAgeCoupleProbabilities[partnerAgeRange]
	        : wifeAgeCoupleProbabilities[partnerAgeRange];
	    string selectedAgeRange <- rnd_choice(partnerProbabilities);
	    list<string> ageParts <- split_with(selectedAgeRange, "-");
	    int minAge <- ageParts[0] as_int 10; // Base-10 conversion
	    int maxAge <- ageParts[1] as_int 10; // Base-10 conversion
	    // Create the new Person for the partner and link them
	    Person newPartner <- getPerson(sex, minAge, maxAge, nil, "", household, false);
	    newPartner.partner <- partner;
	    partner.partner <- newPartner;
	    return newPartner;
	}
	
	int createFamilies(int s) {
	    // Counter for the total number of households created
	    int totalHouseholdsCreated <- 0;
	    // Helper variable for the selected household type
	    string selectedHouseholdType <- "";
	    
	    // Loop: create households until the total number of people reaches numPeople
	    loop while: length(Person) < numPeople {
	        // Choose household size based on global probabilities
	        unknown numMembers <- rnd_choice(householdStructureProbabilities);
	        list<Person> householdMembers <- [];
	        // Initialize a new household with basic parameters
	        create Household number: 1 returns: household {
	            numberPersons <- numMembers;
	            string householdDistrict <- rnd_choice(districtDistributionProbabilities);
	            // Assign residence based on district (building.district attribute)
	            house <- one_of(residential_buildings where (each.district = householdDistrict));
	            if (house = nil) {
	                dataCSV <- dataCSV + string(self);
	            }
	            // If the person does not live in Leganés, assign another city based on entry probabilities
	            bool livesInLeganes <- rnd_choice([true :: 0.59, false :: 0.41]);
	            if (!livesInLeganes) {
	                string leganesEntry <- rnd_choice(leganesEntryProbabilities);
	                map<string, string> cityToSimulationNames <- [
	                    "Alcorcón" :: "Alcorcon",
	                    "Fuenlabrada" :: "Fuenlabrada",
	                    "Getafe" :: "Getafe norte",
	                    "Humanes de Madrid" :: "Extremadura",
	                    "Leganés" :: "Leganés",
	                    "Madrid" :: "Madrid",
	                    "Móstoles" :: "Mostoles"
	                ];
	                leganesEntry <- cityToSimulationNames[leganesEntry];
	                if (!(leganesEntry = "Leganés")) {
	                    house <- first(building where (each.buildingType = "city" and each.buildingName = leganesEntry));
	                }
	            }
	        }
	        // Debug: output the chosen number of members
	        write("nb: " + numMembers);
	        // Create household members according to the number of persons
	        if (numMembers = "1 persona") {
	            // Single-person household
	            selectedHouseholdType <- rnd_choice(householdStructureProbabilities1Person);
	            Person person;
	            switch (selectedHouseholdType) {
	                match "Hogar con una mujer sola menor de 65 años" {
	                    person <- getPerson("Female", 18, 65, nil, selectedHouseholdType, household[0], false);
	                }
	                match "Hogar con un hombre solo menor de 65 años" {
	                    person <- getPerson("Male", 18, 65, nil, selectedHouseholdType, household[0], false);
	                }
	                match "Hogar con una mujer sola de 65 años o más" {
	                    person <- getPerson("Female", 65, 99, nil, selectedHouseholdType, household[0], false);
	                }
	                match "Hogar con un hombre solo de 65 años o más" {
	                    person <- getPerson("Male", 65, 99, nil, selectedHouseholdType, household[0], false);
	                }
	            }
	            householdMembers <- householdMembers + person;
	        }
	        else {
	            if (numMembers = "2 personas") {
	                selectedHouseholdType <- rnd_choice(householdStructureProbabilities2Persons);
	                if (selectedHouseholdType = "Hogar con un solo progenitor que convive con algún hijo menor de 25 años") {
	                    // Single parent with a child under 25 years old
	                    Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child + parent;
	                } else if (selectedHouseholdType = "Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más") {
	                    // Single parent with all children aged 25 or older
	                    Person child <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
	                    Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child + parent;
	                } else if (selectedHouseholdType = "Hogar formado por pareja sin hijos") {
	                    // Couple without children
	                    Person person <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person partner <- matchPartner(person, household[0]);
	                    householdMembers <- householdMembers + person + partner;
	                } else if (selectedHouseholdType = "Otro tipo de hogar") {
	                    // Other household type
	                    Person person1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person person2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + person1 + person2;
	                }
	            }
	            if (numMembers = "3 personas") {
	                selectedHouseholdType <- rnd_choice(householdStructureProbabilities3Persons);
	                if (selectedHouseholdType = "Hogar con un solo progenitor que convive con algún hijo menor de 25 años") {
	                    // Single parent with one child under 25
	                    Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child1 + child2 + parent;
	                } else if (selectedHouseholdType = "Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más") {
	                    // Single parent with all children aged 25 or older
	                    Person child1 <- getPerson(nil, 25, 99, [], selectedHouseholdType, household[0], true);
	                    Person child2 <- getPerson(nil, child1.age, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child1 + child2 + parent;
	                } else if (selectedHouseholdType = "Hogar formado por pareja con hijos en donde algún hijo es menor de 25 años") {
	                    // Couple with at least one child under 25
	                    Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person partner1 <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
	                    Person partner2 <- matchPartner(partner1, household[0]);
	                    householdMembers <- householdMembers + child + partner1 + partner2;
	                } else if (selectedHouseholdType = "Hogar formado por pareja con hijos en donde todos los hijos de 25 años o más") {
	                    // Couple with all children aged 25 or older
	                    Person child <- getPerson(nil, 25, 99, [], selectedHouseholdType, household[0], true);
	                    Person partner1 <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
	                    Person partner2 <- matchPartner(partner1, household[0]);
	                    householdMembers <- householdMembers + child + partner1 + partner2;
	                } else if (selectedHouseholdType = "Hogar formado por pareja o un solo progenitor que convive con algún hijo menor de 25 años y otra(s) persona(s)") {
	                    // Couple or single parent with a child under 25 and other person(s)
	                    Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
	                    Person otherPerson <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child + parent + otherPerson;
	                } else if (selectedHouseholdType = "Otro tipo de hogar") {
	                    // Other household type with three persons
	                    Person p1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p3 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + p1 + p2 + p3;
	                }
	            }
	            if (numMembers = "4 personas") {
	                selectedHouseholdType <- rnd_choice(householdStructureProbabilities4Persons);
	                if (selectedHouseholdType = "Hogar con un solo progenitor que convive con algún hijo menor de 25 años") {
	                    // Single parent with three children where one is under 25
	                    Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person child3 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child1,	child2, child3], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child1 + child2 + child3 + parent;
	                } else if (selectedHouseholdType = "Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más") {
	                    // Single parent with three children all aged 25 or older
	                    Person child1 <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
	                    Person child2 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person child3 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child1 + child2 + child3 + parent;
	                } else if (selectedHouseholdType = "Hogar formado por pareja con hijos en donde algún hijo es menor de 25 años") {
	                    // Couple with children where one is younger than 25
	                    Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person child2 <- getPerson(nil, 25, 35, nil, selectedHouseholdType, household[0], false);
	                    Person partner1 <- getPerson(nil, 18, 99, [child1,	child2], selectedHouseholdType, household[0], false);
	                    Person partner2 <- matchPartner(partner1, household[0]);
	                    householdMembers <- householdMembers + child1 + child2 + partner1 + partner2;
	                } else if (selectedHouseholdType = "Hogar formado por pareja con hijos en donde todos los hijos de 25 años o más") {
	                    // Couple with children all aged 25 or older
	                    Person child1 <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0],	true);
	                    Person child2 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0],	true);
	                    Person partner1 <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
	                    Person partner2 <- matchPartner(partner1, household[0]);
	                    householdMembers <- householdMembers + child1 + child2 + partner1 + partner2;
	                } else if (selectedHouseholdType = "Hogar formado por pareja o un solo progenitor que convive con algún hijo menor de 25 años y otra(s) persona(s)") {
	                    // Couple or single parent with a child under 25 and others
	                    Person child <- getPerson(nil, 0, 25, nil,	selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0],	false);
	                    Person partner <- matchPartner(parent, household[0]);
	                    Person otherPerson <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers +	child + parent + partner + otherPerson;
	                } else if (selectedHouseholdType = "Otro tipo de hogar") {
	                    // Other household type with four persons
	                    Person p1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p2 <- getPerson(nil, 18, 99, nil,	selectedHouseholdType, household[0], false);
	                    Person p3 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p4 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + p1 + p2 + p3 + p4;
	                }
	            }
	            if (numMembers = "5 o más personas") {
	                selectedHouseholdType <- rnd_choice(householdStructureProbabilities5Persons);
	                if (selectedHouseholdType = "Hogar con un solo progenitor que convive con algún hijo menor de 25 años") {
	                    // Single parent with four children, one under 25
	                    Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person child3 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person child4 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child1, child2, child3, child4], selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child1 + child2 + child3 + child4 + parent;
	                } else if (selectedHouseholdType = "Hogar formado por pareja con hijos en donde algún hijo es menor de 25 años") {
	                    // Couple with three children where one is under 25
	                    Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
	                    Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person child3 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
	                    Person partner1 <- getPerson(nil, 18, child1.age + 25, [child1,	child2, child3], selectedHouseholdType, household[0], false);
	                    Person partner2 <- matchPartner(partner1, household[0]);
	                    householdMembers <- householdMembers + child1 + child2 + child3 + partner1 + partner2;
	                } else if (selectedHouseholdType = "Hogar formado por pareja con hijos en donde todos los hijos de 25 años o más") {
	                    // Couple with three children all aged 25 or older
	                    Person child1 <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
	                    Person child2 <- getPerson(nil, 25, child1.age + 10, nil,	selectedHouseholdType, household[0], true);
	                    Person child3 <- getPerson(nil, 25, child1.age + 10, nil,	selectedHouseholdType, household[0], true);
	                    Person partner1 <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
	                    Person partner2 <- matchPartner(partner1, household[0]);
	                    householdMembers <- householdMembers + child1 + child2 + child3 + partner1 + partner2;
	                } else if (selectedHouseholdType = "Hogar formado por pareja o un solo progenitor que convive con algún hijo menor de 25 años y otra(s) persona(s)") {
	                    // Couple or single parent with one child under 25 and two others
	                    Person child <- getPerson(nil, 0, 25, nil,	selectedHouseholdType, household[0], false);
	                    Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0],	false);
	                    Person partner <- matchPartner(parent, household[0]);
	                    Person otherPerson1 <- getPerson(nil, 18, 99, nil,	selectedHouseholdType, household[0], false);
	                    Person otherPerson2 <- getPerson(nil, 18, 99, nil,	selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + child + parent + partner + otherPerson1 + otherPerson2;
	                } else if (selectedHouseholdType = "Otro tipo de hogar") {
	                    // Other household type with five persons
	                    Person p1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p3 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p4 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    Person p5 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
	                    householdMembers <- householdMembers + p1 + p2 + p3 + p4 + p5;
	                }
	            }
	        }
	        
	        // Assign members and type to the newly created household
	        household[0].members <- list<Person>(householdMembers);
	        household[0].householdType <- selectedHouseholdType;
	        households <- households + household;
	        totalHouseholdsCreated <- totalHouseholdsCreated + 1;
	    }
	    // Debug: output total households created
	    write("households: " + length(households));
	    return length(households);
	}

    ///////////////////////////////////////////////////////////////
	// getPerson function: creates a person with his or her characteristics
	///////////////////////////////////////////////////////////////
	Person getPerson(string sex, int minAge, int maxAge, list<Person> children, string householdType, Household household, bool decreasingBias) {
	    // Adjust age limits based on the ages of provided children
	    string motherMaxAgeRange;
	    int oldestChildAge;
	    if (children != nil) {
	        // Find the oldest child’s age
	        oldestChildAge <- max(children collect each.age);
	        // Choose a random maximum age range for the parent
	        motherMaxAgeRange <- rnd_choice(motherAgeProbabilities);
	        // Split the age range string into its numeric parts
	        list<string> ageRangeParts <- split_with(motherMaxAgeRange, "-");
	        // Increase minimum and maximum ages by the oldest child's age
	        minAge <- int(ageRangeParts[0]) + oldestChildAge;
	        maxAge <- int(ageRangeParts[1]) + oldestChildAge;
	    }
	
	    // If decreasingBias is true, bias the maximum age closer to the minimum age
	    if (decreasingBias) {
	        int alpha <- -2;
	        int k <- 2;
	        int increment <- int(k ^ (alpha * (rnd(1))) * (maxAge - minAge));
	        maxAge <- minAge + increment;
	    }
	
	    // Clamp age bounds to valid human age range
	    if (maxAge > 120) {
	        maxAge <- 120;
	    }
	    if (minAge < 0) {
	        minAge <- 0;
	    }
	
	    Person p;
	    // Randomly pick an integer age between minAge and maxAge
	    int ageValue <- rnd(minAge, maxAge, 1);
	    // Determine gender, defaulting to a random choice if sex is nil
	    string gender <- (sex = nil) ? rnd_choice(sexProbabilities) : sex;
	    // Find the corresponding age range label for this age
	    string ageRange <- age_ranges first_with ((split_with(each, "-")[1] as_int 10) >= ageValue);
	    if (ageRange = nil and ageValue > 120) {
	        ageRange <- "100-120";
	    }
	    // Update the global age distribution count
	    int selectedIndex <- age_ranges index_of ageRange;
	    age_counts[selectedIndex] <- age_counts[selectedIndex] + 1;
	
	    // Generate work schedule and sleep time
	    int startWork <- rnd(minWorkStart, maxWorkStart);
	    int endWork <- rnd(minWorkEnd, maxWorkEnd);
	    int hoursSleep <- rnd(7, 9);
	    int calculatedBedtime <- (startWork - hoursSleep) > 0
	        ? (startWork - hoursSleep)
	        : (24 + (startWork - hoursSleep));
	    write("start_work: " + startWork + " hours_sleep: " + hoursSleep + " bedtime: " + calculatedBedtime);
	
	    // Random walking/driving speed
	    float speedValue <- rnd(minSpeed, maxSpeed);
	    // Assign living place from the household and leave working place empty for now
	    building livingPlace <- household.house;
	    building workingPlace <- nil;
	
	    // Create and initialize the Person object
	    create Person with: [
	        age_range    :: ageRange,
	        gender       :: gender,
	        age          :: ageValue,
	        start_work   :: startWork,
	        end_work     :: endWork,
	        speed        :: speedValue,
	        living_place :: livingPlace,
	        working_place:: workingPlace,
	        bedtime      :: calculatedBedtime
	    ] returns: ret;
	    p <- ret[0];
	
	    // If children are provided, assign parental links accordingly
	    if (children != nil) {
	        loop child over: children {
	            // If this parent is not male, assign as father; otherwise assign as mother
	            if (p.gender != "Male") {
	                child.father <- p;
	                p.children <- children;
	            } else {
	                child.mother <- p;
	            }
	        }
	        p.children <- children;
	    }
	
	    // Log a summary of the created Person
	    write(
	        "Person created with name " + p.name +
	        " Age Range: "   + p.age_range +
	        ", Gender: "     + p.gender +
	        ", Age: "        + p.age +
	        ", Start Work Hour: " + p.start_work +
	        ", End Work Hour: "   + p.end_work +
	        ", Speed: "      + p.speed +
	        ", Living Place: " + p.living_place +
	        ", Working Place: " + p.working_place
	    );
	    return p;
	}
}
    
/**
 * 
     █████╗  ██████╗  ███████╗███╗   ██╗████████╗███████╗
    ██╔══██╗██╔═════╗╗██╔════╝████╗  ██║╚══██╔══╝██╔════╝
    ███████║██║     ║║█████╗  ██╔██╗ ██║   ██║   ███████╗
    ██╔══██║██║   ██║║██╔══╝  ██║╚██╗██║   ██║   ╚════██║
    ██║  ██║╚██████╔╝╝███████╗██║ ╚████║   ██║   ███████║
    ╚═╝  ╚═╝ ╚═════╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝
	This code defines agents
  */ 
// Agent in charge of updating the simulation time monitor.
species datetime_keeper {
    string current_datetime;

    reflex update_datetime {
        // Display the current date and time in "Date: YYYY-MM-DD HH:MM:SS" format
        current_datetime <- "Date: " +
            string(current_date.year) + "-" +
            (current_date.month < 10 ? "0" + string(current_date.month) : string(current_date.month)) + "-" +
            (current_date.day < 10 ? "0" + string(current_date.day) : string(current_date.day)) + " " +
            (current_date.hour < 10 ? "0" + string(current_date.hour) : string(current_date.hour)) + ":" +
            (current_date.minute < 10 ? "0" + string(current_date.minute) : string(current_date.minute)) + ":" +
            (current_date.second < 10 ? "0" + string(current_date.second) : string(current_date.second));
    }
}


// Database agent for reading simulation statistics
species databaseReader skills: [SQLSKILL] {
    // Map of database connection parameters
    map<string, string> PARAMS <- [
        'dbtype'      :: 'sqlite',
        'database'    :: '../includes/SimuCityDB.db'
    ];

    // Read household structure probabilities for a given municipality and household size
    action readHouseholdStructureProbabilities(string municipality, string householdSize) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT EstructuraHogar, ROUND(Total * 1.0 / (SELECT Total FROM Hogares WHERE Municipio = ? AND TamanoHogar = ? AND EstructuraHogar = 'Total (estructura del hogar)'), 2) AS Porcentaje FROM Hogares WHERE Municipio = ? AND TamanoHogar = ? AND EstructuraHogar != 'Total (estructura del hogar)'", 
            values: [municipality, householdSize, municipality, householdSize]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector; 
    }

    // Read maximum mother age distribution for a given autonomous community
    action readMotherMaxAgeProbabilities(string autonomousCommunity) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH EdadMadreSinTotal AS (SELECT Edad_Madre_Transformada, Total FROM edadMadre WHERE Edad_Madre_Transformada <> 'Total' AND Comunidades_Ciudades_Autonomas = ?) SELECT Edad_Madre_Transformada, ROUND((CAST(Total AS FLOAT) / SUM(Total) OVER ()), 3) AS Porcentaje FROM EdadMadreSinTotal;", 
            values: [autonomousCommunity]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector; 
    }

    // Read gender distribution probabilities for a given province
    action readSexProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH SexoPorcentaje AS (SELECT Sexo, Total, SUM(Total) OVER () AS TotalGeneral FROM SexoPorMunicipios WHERE Provincias = ?) SELECT Sexo, ROUND((CAST(Total AS FLOAT) / TotalGeneral), 2) AS Probabilidad FROM SexoPorcentaje;", 
            values: [province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector; 
    }

    // Read partner orientation probabilities for a given province
    action readOrientationProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH SumaTotal AS (SELECT SUM(CASE WHEN Tipo_Pareja = 'Pareja de distinto sexo' THEN Total ELSE 0 END) AS TotalHetero, SUM(CASE WHEN Tipo_Pareja IN ('Pareja de distinto sexo', 'Pareja del mismo sexo, femenino', 'Pareja del mismo sexo, masculino') THEN Total ELSE 0 END) AS TotalParejas FROM parejas WHERE Provincias = ?) SELECT ROUND(CAST(TotalHetero AS FLOAT) / TotalParejas, 3) AS ProbabilidadHeterosexual, ROUND(1 - (CAST(TotalHetero AS FLOAT) / TotalParejas), 3) AS ProbabilidadHomosexual FROM SumaTotal;", 
            values: [province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            // Assumes the query returns two columns: category and its probability
            string category <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(category::value);
        }
        return probabilityVector; 
    }

    // Read age group distribution probabilities for a given province
    action readAgeGroupProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalPorGrupo AS (SELECT Edad_Grupos_Quinquenales_Transformado AS GrupoEdad, SUM(Total) AS TotalGrupo FROM gruposDeEdad WHERE Sexo = 'Ambos sexos' AND Provincias = ? GROUP BY Edad_Grupos_Quinquenales_Transformado), TotalProvincia AS (SELECT SUM(Total) AS TotalProvincia FROM gruposDeEdad WHERE Sexo = 'Ambos sexos' AND Provincias = ?) SELECT GrupoEdad, ROUND(CAST(TotalGrupo AS FLOAT) / TotalProvincia.TotalProvincia, 4) AS Porcentaje FROM TotalPorGrupo, TotalProvincia;", 
            values: [province, province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector; 
    }

    // Read entry or exit probabilities for Leganés based on type ("entrada" or "salida")
    action readLeganesEntryExitProbabilities(string type) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT Municipio, CASE WHEN ? = 'entrada' THEN Probabilidad_Entradas WHEN ? = 'salida' THEN Probabilidad_Salidas ELSE NULL END AS Probabilidad FROM entradasYSalidasLeganes;", 
            values: [type, type]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector;
    }

    // Read district distribution probabilities for Leganés
    action readDistrictProbabilities {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT Distrito, Total_porcentaje FROM DistribucionDistritosLeganes WHERE Distrito <> 'TOTALES' ORDER BY Distrito;", 
            values: []
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector;
    }

    // Read husband age coupling probabilities for a given province and wife age
    action readHusbandAgeCoupleProbabilities(string province, string age) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalPorEdad AS (SELECT Edad_Esposos_Transformada, Edad_Esposas_Transformada, Total FROM diferenciaEdadParejas WHERE Provincia = ? AND Edad_Esposos_Transformada = ?) , SumaTotal AS (SELECT SUM(Total) AS SumaTotalEsposas FROM TotalPorEdad) SELECT t.Edad_Esposos_Transformada, t.Edad_Esposas_Transformada, t.Total, ROUND(t.Total * 1.0 / s.SumaTotalEsposas, 3) AS Probabilidad FROM TotalPorEdad t JOIN SumaTotal s ON 1=1 ORDER BY t.Edad_Esposas_Transformada;", 
            values: [province, age]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[1] as string; // use wife's age as the key
            float value <- ls[3] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector; 
    }

    // Read wife age coupling probabilities for a given province and husband age
    action readWifeAgeCoupleProbabilities(string province, string age) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalPorEdad AS (SELECT Edad_Esposas_Transformada, Edad_Esposos_Transformada, Total FROM diferenciaEdadParejas WHERE Provincia = ? AND Edad_Esposas_Transformada = ?) , SumaTotal AS (SELECT SUM(Total) AS SumaTotalEsposos FROM TotalPorEdad) SELECT t.Edad_Esposas_Transformada, t.Edad_Esposos_Transformada, t.Total, ROUND(t.Total * 1.0 / s.SumaTotalEsposos, 3) AS Probabilidad FROM TotalPorEdad t JOIN SumaTotal s ON 1=1 ORDER BY t.Edad_Esposos_Transformada;", 
            values: [province, age]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: results[2] {
            string key <- ls[1] as string; // use husband's age as the key
            float value <- ls[3] as float;
            probabilityVector <- probabilityVector + map<string, float>(key::value);
        }
        return probabilityVector; 
    }

    // Read a random sample of vehicle data based on a percentage of the population
    action readVehicleProbabilities(float percentage) {
        int num_to_select <- round(percentage * numPeople);
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH VehiculosFiltrados AS ( SELECT Marca, Submarca, Version, Comb AS Combustible, CO2_g_km FROM vehiculos WHERE Categoria != 'AUTOS DE LUJO' ) SELECT Marca, Submarca, Version, Combustible, CO2_g_km FROM VehiculosFiltrados ORDER BY RANDOM() LIMIT ?;", 
            values: [num_to_select]
        ));
        list<map<string, string>> selectedVehicles <- list<map<string, string>>([]);
        loop ls over: results[2] {
            string brand <- ls[0] as string;
            string subbrand <- ls[1] as string;
            string version <- ls[2] as string;
            string fuel <- ls[3] as string;
            string co2 <- ls[4] as string;
            selectedVehicles <- selectedVehicles + [
                map<string, string>(
                    "Brand"    :: brand,
                    "Subbrand" :: subbrand,
                    "Version"  :: version,
                    "Fuel"     :: fuel,
                    "CO2_g_km" :: co2
                )
            ];
        }
        return selectedVehicles;
    }

    // Calculate household size percentages for a given municipality
    action calculateHouseholdPercentages(string municipality) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalHogarMunicipio AS ( SELECT SUM(Total) AS TotalMunicipio FROM Hogares WHERE Municipio = ? AND TamanoHogar NOT IN ('Total', 'Total (tamaño del hogar)') ) SELECT TamanoHogar, ROUND(SUM(Total) * 1.0 / (SELECT TotalMunicipio FROM TotalHogarMunicipio), 2) AS Porcentaje FROM Hogares WHERE Municipio = ? AND TamanoHogar NOT IN ('Total', 'Total (tamaño del hogar)') GROUP BY TamanoHogar;", 
            values: [municipality, municipality]
        ));
        map<string, float> percentageVector <- map<string, float>(map([]));
        loop row over: results[2] {
            string size <- row[0] as string;
            float perc <- row[1] as float;
            percentageVector <- percentageVector + map<string, float>(size::perc);
        }
        return percentageVector;
    }
    
    // Initializer: read and assign all probability vectors from the database
    init {
        householdStructureProbabilities       <- calculateHouseholdPercentages(statisticsCity);
        householdStructureProbabilities1Person <- readHouseholdStructureProbabilities(statisticsCity, "1 persona");
        householdStructureProbabilities2Persons <- readHouseholdStructureProbabilities(statisticsCity, "2 personas");
        householdStructureProbabilities3Persons <- readHouseholdStructureProbabilities(statisticsCity, "3 personas");
        householdStructureProbabilities4Persons <- readHouseholdStructureProbabilities(statisticsCity, "4 personas");
        householdStructureProbabilities5Persons <- readHouseholdStructureProbabilities(statisticsCity, "5 o más personas");
        motherAgeProbabilities                <- readMotherMaxAgeProbabilities(statisticsAutonomousCommunity);
        sexProbabilities                      <- readSexProbabilities(statisticsProvince);
        orientationProbabilities              <- readOrientationProbabilities(statisticsProvince);
        ageGroupProbabilities                 <- readAgeGroupProbabilities(statisticsProvince);
        loop age over: ["15-19", "20-24", "25-29", "30-34", "35-39", "40-44", "45-49", "50-54", "55-59", "60-99"] {
            husbandAgeCoupleProbabilities[age] <- readHusbandAgeCoupleProbabilities(statisticsProvince, age);
            wifeAgeCoupleProbabilities[age]    <- readWifeAgeCoupleProbabilities(statisticsProvince, age);
        }
        leganesEntryProbabilities             <- readLeganesEntryExitProbabilities("entrada");
        leganesExitProbabilities              <- readLeganesEntryExitProbabilities("salida");
        districtDistributionProbabilities     <- readDistrictProbabilities();
        vehicleConsumptionMatrix              <- readVehicleProbabilities(0.4);
    }
}

// Crossroads agent using the intersection_skill
species crossroads skills: [intersection_skill] {
    // Intersection type flags
    bool isTrafficLight;
    bool isYield;
    bool isStop;
    bool isZebraCrossing;
    bool isNotFinishPoint;
    bool isStreet;
    bool isBusStop;
    bool isBusStation;
    bool isChargingPoint;
    bool isTurningCircle;
    bool isCrossroad;
    bool isTrainStation;
    string nameTrainStation;
    bool isCity;
    string nameCity;
    bool isMidPoint;
    bool crossroadsNoInitialLocation <- false;  // Prevent route start/end here

    // Traffic light timing parameters
    float timeToChangeRedToGreen;
    float timeToChangeGreenToFixedYellow;
    float timeToChangeFixedYellowToRed;
    float counter;

    // Adjacent road lists for traffic control
    list<roads> ways1;
    list<roads> ways2;

    // Signal light color and state flags
    rgb colorLight;
    bool isGreen;
    bool isRed;
    bool isFixedYellow;

    // Electric charging station attributes
    string typeCharge;
    int subType;
    float maxTension;
    float maxElectricity;
    float maxPower;
    float timeRecharge;
    bool hasCCS2 <- false;
    bool hasType2 <- false;
    bool hasChaDeMo <- false;

    // Pedestrian and vehicle crossing flags
    bool pedestrianCrossing <- false;
    bool vehicleCrossing <- false;

    // Waiting passengers list for train stations
    list<Person> waitingPassengers <- nil;

    // Initialization action for the intersection
    action initialize {
        self.name <- "crossroads" + (index);
        // Set phase durations based on current hour
        if ((current_date.hour >= 7) and (current_date.hour <= 10)) {
            timeToChangeRedToGreen <- 80.0;
            timeToChangeGreenToFixedYellow <- 60.0;
            timeToChangeFixedYellowToRed <- 5.0;
        } else if ((current_date.hour >= 14) and (current_date.hour <= 16)) {
            timeToChangeRedToGreen <- 80.0;
            timeToChangeGreenToFixedYellow <- 60.0;
            timeToChangeFixedYellowToRed <- 5.0;
        } else if ((current_date.hour >= 19) and (current_date.hour <= 21)) {
            timeToChangeRedToGreen <- 70.0;
            timeToChangeGreenToFixedYellow <- 60.0;
            timeToChangeFixedYellowToRed <- 5.0;
        } else {
            timeToChangeRedToGreen <- 40.0;
            timeToChangeGreenToFixedYellow <- 110.0;
            timeToChangeFixedYellowToRed <- 5.0;
        }
        counter <- rnd(timeToChangeGreenToFixedYellow);

        // Prepare traffic control if applicable
        if (isTrafficLight or isZebraCrossing or isStop or isYield or isTrainStation) {
            do computeTraffic;
            stop << [];
        }

        // Initialize passenger queue for train stations
        if (isTrainStation) {
            waitingPassengers <- [];
        }

        // Randomize initial light state
        if (isTrafficLight) {
            if (flip(0.33)) {
                do changeToGreen;
            } else if (flip(0.33)) {
                do changeToFixedYellow;
            } else {
                do changeToRed;
            }
        }

        // Disable routing start/end at controlled nodes
        if (isTrafficLight or isStreet or isYield or isStop or isZebraCrossing or isBusStop or isNotFinishPoint or isChargingPoint or isTurningCircle) {
            crossroadsNoInitialLocation <- true;
        } else {
            crossroadsNoInitialLocation <- false;
        }
    }

    bool controladorComputeTraffic <- (isTrafficLight or isZebraCrossing or isStop or isYield);

    // Classify adjacent roads into two groups based on angle
    action computeTraffic {
        ways1 <- [];
        ways2 <- [];
        if (length(roads_in) >= 2) {
            roads firstRoad <- roads(roads_in[0]);
            list<point> firstRoadPoints <- firstRoad.shape.points;
            float referenceAngle <- float(last(firstRoadPoints) direction_to firstRoad.location);
            loop eachRoad over: roads_in {
                list<point> eachRoadPoints <- roads(eachRoad).shape.points;
                float destinationAngle <- float(last(eachRoadPoints) direction_to eachRoad.location);
                float angle <- abs(destinationAngle - referenceAngle);
                if ((angle > 45 and angle < 135) or (angle > 225 and angle < 315)) {
                    ways2 << roads(eachRoad);
                }
            }
        }
        // Any roads not in ways2 go to ways1
        loop eachRoad over: roads_in {
            if (not (roads(eachRoad) in ways2)) {
                ways1 << roads(eachRoad);
            }
        }
    }

    // Switch signal to green phase
    action changeToGreen {
        stop <- list<list>(ways2);
        colorLight <- #green;
        isGreen <- true;
        isRed <- false;
        isFixedYellow <- false;
    }
    // Switch signal to red phase
    action changeToRed {
        stop <- list<list>(ways1);
        colorLight <- #red;
        isGreen <- false;
        isRed <- true;
        isFixedYellow <- false;
    }
    // Switch signal to fixed yellow phase
    action changeToFixedYellow {
        stop <- list<list>(ways1);
        colorLight <- #yellow;
        isGreen <- false;
        isRed <- false;
        isFixedYellow <- true;
    }

    // Reflex to cycle traffic light phases dynamically
    reflex dynamicNode when: isTrafficLight {
        counter <- counter + step;
        if (isFixedYellow) {
            if (counter >= timeToChangeFixedYellowToRed) {
                counter <- 0.0;
                do changeToRed;
            }
        } else {
            if (isGreen) {
                if (counter >= timeToChangeGreenToFixedYellow) {
                    counter <- 0.0;
                    do changeToFixedYellow;
                }
            } else {
                if (counter >= timeToChangeRedToGreen) {
                    counter <- 0.0;
                    do changeToGreen;
                }
            }
        }
    }

    // Visual representation of the node
    aspect default {
        if (render3D) {
            if (isTrafficLight) {
                draw box(1, 1, 10) color: #black;
                draw sphere(3) at: {location.x, location.y, 10} color: colorLight;
            } else if (typeCharge != "") {
                draw box(1, 1, 10) color: #black;
                draw sphere(3) at: {location.x, location.y, 10} color: #purple;
            }
        } else {
            if (isTrafficLight) {
                draw rectangle(2, 2) color: #black;
                draw circle(1) color: colorLight;
                if (length(ways2) > 0) {
                    draw rectangle(2, 2) at: {location.x, location.y - 2} color: #black;
                    draw circle(1) color: colorLight = #green ? #red : #green at: {location.x, location.y - 2};
                }
            }
            else if (isStop) {
                draw circle(1) color: #black;
                draw circle(0.75) color: #red;
                draw rectangle(1, 0.5) color: #white;
            }
            else if (isYield) {
                draw triangle(3) color: #red;
                draw triangle(2) color: #white;
            }
            else if (isZebraCrossing) {
                draw rectangle(3, 1) color: #black;
                draw rectangle(1, 1) color: #white;
            }
            else if (isChargingPoint) {
                draw circle(4) color: #purple;
                if (showTextChargingPoints) {
                    string chargersString <- (hasCCS2 ? "" : "CCS2\n") + (hasType2 ? "" : "Type2\n") + (hasChaDeMo ? "" : "ChaDeMo\n");
                    draw string(chargersString) size: 0.01 color: #black;
                }
            }
        }
    }
}
// Roads agent using the road_skill
species roads skills: [road_skill] {
    geometry geometryDisplayForMood3D;
    int lanes;
    string oneway;
    string vehh;
    // int veh_h <- 0;  // To store the number of vehicles per hour

    // Reflex activated every simulation hour
    reflex update_traffic {
        // Use all_agents to count vehicles on this road
        int nAgents <- length(self.all_agents);
        // veh_h <- veh_h + nAgents;
    }

    aspect default {
        if (render3D) {
            if (watchDirections) {
                draw geometryDisplayForMood3D color: #white end_arrow: 2;
            } else {
                draw geometryDisplayForMood3D color: #white;
            }
        } else {
            if (watchDirections) {
                draw shape color: #white end_arrow: 2;
            } else {
                draw shape color: #white;
            }
        }
    }
	/* 
    aspect distribution_traffic {
        if (vehh != "") {
            if (veh_h < 500) {
                draw shape color: #blue end_arrow: 2;
            } else if (veh_h >= 500 and veh_h < 1000) {
                draw shape color: #cyan end_arrow: 2;
            } else if (veh_h >= 1000 and veh_h < 1500) {
                draw shape color: #green end_arrow: 2;
            } else if (veh_h >= 1500 and veh_h < 2000) {
                draw shape color: #yellow end_arrow: 2;
            } else {
                draw shape color: #red end_arrow: 2;
            }
        } else {
            draw shape color: #gray end_arrow: 2;
        }
    }*/
}

// Streets agent
species streets {
    rgb color <- #silver;

    aspect default {
        // Draw streets in silver
        if (render3D) {
            draw shape color: color;
        } else {
            draw shape color: color;
        }
    }
}

// Building agent
species building {
    string buildingName;
    string buildingType;
    string leisureType;
    string railwayType;
    string district;       // Renamed from "districtB" to "district"
    geometry geom_display;
    int buildingHeight;

    aspect default {
        if (render3D) {
            // Color building based on its type or leisure category
            if (buildingType = "school" or buildingType = "university" or buildingType = "kindergarten" or buildingType = "college") {
                draw shape color: rgb(173, 216, 230) depth: buildingHeight;
            } else if (buildingType = "apartments" or buildingType = "detached" or buildingType = "dormitory" or buildingType = "house" or buildingType = "semidetached_house" or buildingType = "construction" or buildingType = "residential") {
                draw shape color: rgb(255, 160, 122) depth: buildingHeight;
            } else if (buildingType = "commercial" or buildingType = "retail" or buildingType = "office" or buildingType = "kiosk" or buildingType = "public" or buildingType = "government" or buildingType = "civic") {
                draw shape color: rgb(144, 238, 144) depth: buildingHeight;
            } else if (buildingType = "church") {
                draw shape color: rgb(128, 0, 128) depth: buildingHeight;
            } else if (buildingType = "hospital") {
                draw shape color: rgb(255, 69, 0) depth: buildingHeight;
            } else if (buildingType = "sports_centre" or buildingType = "sports_hall" or buildingType = "stadium" or buildingType = "pavilion" or buildingType = "terrace") {
                draw shape color: rgb(255, 215, 0) depth: buildingHeight;
            } else if (buildingType = "industrial" or buildingType = "warehouse" or buildingType = "garage" or buildingType = "farm_auxiliary" or buildingType = "shed" or buildingType = "service") {
                draw shape color: rgb(169, 169, 169) depth: buildingHeight;
            } else if (buildingType = "train_station" or buildingType = "transportation" or buildingType = "parking") {
                draw shape color: rgb(220, 20, 60) depth: buildingHeight;
            } else if (buildingType = "roof" or buildingType = "ruins" or buildingType = "yes" or buildingType = "transformer_tower" or buildingType = "cabin" or buildingType = "carport") {
                draw shape color: rgb(211, 211, 211) depth: buildingHeight;
            } else if (leisureType = "garden" or leisureType = "park" or leisureType = "nature_reserve") {
                draw shape color: rgb(144, 238, 144) depth: 0;
            } else if (leisureType = "playground" or leisureType = "sports_centre" or leisureType = "pitch" or leisureType = "swimming_pool" or leisureType = "water_park" or leisureType = "stadium" or leisureType = "track") {
                draw shape color: rgb(255, 182, 193) depth: buildingHeight;
            } else {
                draw shape color: rgb(144, 238, 144) depth: buildingHeight;
            }
        } else {
            // 2D rendering uses the same color logic without depth
            if (buildingType = "school" or buildingType = "university" or buildingType = "kindergarten" or buildingType = "college") {
                draw shape color: rgb(173, 216, 230);
            } else if (buildingType = "apartments" or buildingType = "detached" or buildingType = "dormitory" or buildingType = "house" or buildingType = "semidetached_house" or buildingType = "construction" or buildingType = "residential") {
                draw shape color: rgb(255, 160, 122);
            } else if (buildingType = "commercial" or buildingType = "retail" or buildingType = "office" or buildingType = "kiosk" or buildingType = "public" or buildingType = "government" or buildingType = "civic") {
                draw shape color: rgb(144, 238, 144);
            } else if (buildingType = "church") {
                draw shape color: rgb(128, 0, 128);
            } else if (buildingType = "hospital") {
                draw shape color: rgb(255, 69, 0);
            } else if (buildingType = "sports_centre" or buildingType = "sports_hall" or buildingType = "stadium" or buildingType = "pavilion" or buildingType = "terrace") {
                draw shape color: rgb(255, 215, 0);
            } else if (buildingType = "industrial" or buildingType = "warehouse" or buildingType = "garage" or buildingType = "farm_auxiliary" or buildingType = "shed" or buildingType = "service") {
                draw shape color: rgb(169, 169, 169);
            } else if (buildingType = "train_station" or buildingType = "transportation" or buildingType = "parking") {
                draw shape color: rgb(220, 20, 60);
            } else if (buildingType = "roof" or buildingType = "ruins" or buildingType = "yes" or buildingType = "transformer_tower" or buildingType = "cabin" or buildingType = "carport") {
                draw shape color: rgb(211, 211, 211);
            } else if (leisureType = "garden" or leisureType = "park" or leisureType = "nature_reserve") {
                draw shape color: rgb(144, 238, 144);
            } else if (leisureType = "playground" or leisureType = "sports_centre" or leisureType = "pitch" or leisureType = "swimming_pool" or leisureType = "water_park" or leisureType = "stadium" or leisureType = "track") {
                draw shape color: rgb(255, 182, 193);
            } else {
                draw shape color: rgb(211, 211, 211);
            }
        }
    }
}


// Species modeling household units
species Household {
    string houseNumber;
    string householdType;       // Type of household (e.g., family structure)
    list<Person> members;       // List of persons in this household
    string numberPersons;       // Number of members as string
    string district;            // District where the house is located
    building house;             // Reference to the building object
    init {
        members <- [];          // Initialize the members list
    }
}


// Train track agent using road_skill
species railway skills: [road_skill] {
    aspect default {
        draw shape color: #red; // Render railway tracks in red
    }
}


// Train agent using driving skill
species train skills: [driving] {
    rgb color <- #white;                // Color of the train
    bool breakdown <- false;            // Indicates if the train has broken down
    float probabilityBreakdown;         // Probability of breakdown occurrence
    bool trainStopInAStop;              // Flag for stopping at a station
    float timeToStopInAStop <- 60.0;    // Time to remain stopped at a station (seconds)
    float contStop <- 0.0;              // Counter tracking stop duration
    crossroads initialCrossroad;        // Starting crossroads reference
    crossroads targetCrossroads;        // Destination crossroads reference
    int thresholdStucked;               // Threshold for being stuck
    float counterStucked <- 0.0;        // Counter for time stuck
    list<Person> passengers <- [];      // List of onboard passengers

    // Control train traffic at crossings
    action trafficControlTrain {
        if (current_target != nil) {
            crossroads nextCrossroad <- crossroads(current_target);
            if (distance_to_current_target <= 16 #meters) {
                trainStopInAStop <- true;
                nextCrossroad.stop[0] <- nextCrossroad.roads_out;
            }
        }
    }
    
    // Handle arrival at train stations
    reflex arriveTrainStation when: current_path != nil and final_target != nil and trainStopInAStop = true {
        crossroads nextCrossroad <- crossroads(current_target);
        if (contStop < timeToStopInAStop) {
            contStop <- contStop + step;   // Increment stop counter
        } else {
            if (current_target != final_target) {
                // Disembark passengers whose target is this station
                list<Person> passengersToSimulatedCity <- passengers where(each.the_target != nil);
                list<Person> passengersGettingOff <- passengersToSimulatedCity where(current_target.name contains (each.the_target.buildingName));
                loop ps over: passengersGettingOff {
                    ps.the_target <- ps.the_final_target;
                    ps.startJourney <- true;
                }
                passengers <- passengers - passengersGettingOff;
            }
            else {
                // Final destination reached: move all remaining passengers to target point
                loop ps over: passengers {
                    ps.location <- point(ps.the_final_target);
                }
                passengers <- [];
            }
            // Board waiting passengers
            passengers <- passengers + nextCrossroad.waitingPassengers;
            nextCrossroad.waitingPassengers <- [];
            trainStopInAStop <- false;
            contStop <- 0.0;                // Reset stop counter
            nextCrossroad.stop[0] <- [];    // Clear stop control
        }
    }
    
    // Normal movement when not stopped
    reflex moveNormalTrains when: current_path != nil and final_target != nil and trainStopInAStop = false {
        do drive;                         // Perform driving action
        if (final_target != nil) {
            do trafficControlTrain;       // Apply traffic control at crossings
        } else {
            // Swap initial and target crossroads for return trip
            crossroads aux <- targetCrossroads;
            targetCrossroads <- initialCrossroad;
            initialCrossroad <- aux;
            trainStopInAStop <- false;
        }
    }
    
    // Dispatch train when no final target is set
    reflex timeToGoNormalTrains when: final_target = nil and trainStopInAStop = false {
        self.location <- point(initialCrossroad);
        current_path <- compute_path(graph: tracksNetwork, target: targetCrossroads);
        if (current_path = nil) {
            // No path found, error handling omitted
        }
    }
    
    // Handle random breakdown events
    reflex breakdown when: flip(probabilityBreakdown) {
        breakdown <- true;
        max_speed <- 5 #km / #h;         // Reduce speed after breakdown
    }
    
    aspect default {
        if (render3D) {
            // 3D train shape: rectangle body with triangle front
            draw rectangle(5, 30) + triangle(5) depth: 1 color: color;
        } else {
            // 2D train shape: rotated rectangle and triangle
            draw (rectangle(5, 30) rotated_by 20 + triangle(5) rotated_by 20) color: color;
        }
    }
}

// Abstract vehicle agent with basic behavior for all simulator vehicles
species vehicles skills: [driving] {
    // Color and randomized appearance
    rgb color <- #brown;
    rgb rndcolor <- rnd_color(255);
    
    // Breakdown state and probability
    bool breakdown <- false;
    float probabilityBreakdown;
    
    // Flags for stopping at crossings and signs
    bool carStopInAZebraCrossing;
    bool carStopInAYield;
    bool carStopInAStop;
    bool carInAYield <- false;
    bool checkCarsYield;
    
    // Stop durations for different control types
    float timeToStopInAStop <- 5.0;
    float timeToStopInAZebraCrossing <- 5.0;
    float contStop <- 0.0;
    
    // References to route intersections
    crossroads initialCrossroad;
    crossroads targetCrossroads;
    
    // Congestion tracking variables
    float thresholdStucked;
    float counterStucked <- 0.0;
    
    // Detection distances (from globals)
    float closeDistance <- closeDistance;
    float farDistance <- farDistance;
    
    // Route control state
    bool traveling <- false;
    int numStepsClose <- 0;
    int numStepsFar <- 0;
    
    // Passenger list
    list<Person> passengers <- [];
    
    // Yield/stop blocking state
    bool isBlocked;
    crossroads nextToYieldCrossroad;
    
    // Upcoming intersection signal type flags
    bool nextIsStop <- false;
    bool nextIsYield <- false;
    bool nextIsZebra <- false;
    
    // Compute lateral offset for lane positioning
    point compute_position {
        if (current_road != nil) {
            float dist <- (roads(current_road).lanes - current_lane - mean(range(num_lanes_occupied - 1)) - 0.5) * lane_width;
            if (violating_oneway) {
                dist <- -dist;
            }
            point shift_pt <- { cos(heading + 90) * dist, sin(heading + 90) * dist };
            return location + shift_pt;
        } else {
            return {0, 0};
        }
    }
    
    // Base visual representation of the vehicle
    aspect base {
        if (current_road != nil) {
            point pos <- compute_position();
            draw rectangle(vehicle_length, lane_width * num_lanes_occupied) 
                at: pos color: rndcolor rotate: heading border: #black;
            draw triangle(lane_width * num_lanes_occupied) 
                at: pos color: #white rotate: heading + 90 border: #black;
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Action: Determine next intersection control type
    /////////////////////////////////////////////////////////////
    action trafficControl {
        if (current_target != nil) {
            crossroads nextCrossroad <- crossroads(current_target);
            // Yield sign logic
            if (nextCrossroad.isYield) {
                nextIsYield <- true;
            }
            if (nextIsYield and not(nextCrossroad.isYield)) {
                carInAYield <- true;
            }
            // Stop sign logic
            if (nextCrossroad.isStop) {
                nextIsStop <- true;
            }
            if (nextIsStop and not(nextCrossroad.isStop)) {
                carStopInAStop <- true;
                nextIsStop <- false;
            }
            // Zebra crossing logic
            else if (nextCrossroad.isZebraCrossing) {
                if (distance_to_current_target <= closeDistance #meters) {
                    if (nextCrossroad.pedestrianCrossing) {
                        carStopInAZebraCrossing <- true;
                        nextCrossroad.stop <- [] + (roads(current_road));
                    }
                }
            }
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Pause at zebra crossings until cleared
    /////////////////////////////////////////////////////////////
    reflex stopToZebraCrossing when: current_path != nil and final_target != nil and carStopInAZebraCrossing = true and carStopInAStop = false and carStopInAYield = false {
        crossroads nextCrossroad <- crossroads(current_target);
        isBlocked <- false;
        contStop <- contStop + step;
        if (contStop < timeToStopInAZebraCrossing) {
            isBlocked <- true;
        } else {
            if (nextCrossroad.pedestrianCrossing) {
                isBlocked <- true;
            }
        }
        if (isBlocked) {
            nextCrossroad.stop <- list<list>(current_road);
        } else {
            nextCrossroad.stop <- [];
            carStopInAZebraCrossing <- false;
            contStop <- 0.0;
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Pause at yield signs if cross traffic is present
    /////////////////////////////////////////////////////////////
    reflex stopToYield when: current_path != nil and final_target != nil and carStopInAZebraCrossing = false and carStopInAStop = false and carInAYield = true {
        isBlocked <- false;
        crossroads nextCrossroad <- crossroads(current_target);
        roads nextRoad <- roads(next_road);
        loop k over: nextCrossroad.roads_in {
            if (roads(k) != current_road and roads(k).agents_on != []) {
                isBlocked <- true;
            }
        }
        if (isBlocked) {
            nextCrossroad.stop[0] <- [] + roads(next_road);
            carStopInAYield <- true;
        } else {
            nextCrossroad.stop <- [];
            carStopInAYield <- false;
            carInAYield <- false;
            nextIsYield <- false;
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Pause at stop signs until cleared
    /////////////////////////////////////////////////////////////
    reflex stopToStop when: current_path != nil and final_target != nil and carStopInAZebraCrossing = false and carStopInAStop = true and carStopInAYield = false {
        contStop <- contStop + step;
        isBlocked <- false;
        crossroads nextCrossroadStop <- crossroads(current_target);
        roads nextRoad1 <- roads(next_road);
        if (contStop < timeToStopInAStop) {
            isBlocked <- true;
        } else {
            loop k over: nextCrossroadStop.roads_in {
                if (roads(k) != nextRoad1 and roads(k).agents_on != []) {
                    isBlocked <- true;
                }
            }
        }
        if (isBlocked) {
            nextCrossroadStop.stop <- [] + roads(current_road);
        } else {
            nextCrossroadStop.stop <- [];
            carStopInAStop <- false;
            contStop <- 0.0;
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Simulate vehicle breakdown
    /////////////////////////////////////////////////////////////
    reflex breakdown when: flip(probabilityBreakdown) {
        breakdown <- true;
        max_speed <- 5 #km / #h;
    }
}

// Normal cars agent inheriting from vehicles with advanced driving logic
species normalCars parent: vehicles {
    int numTimesCurrentPathNull <- 0;
    crossroads nextNode;
    // CO2 consumption tracking
    string carModel;
    string fuel;
    float CO2_g_km;
    float consumoCO2 <- 0.0;
    
    // Reflex: Plan route when idle
    reflex timeToGoNormalCars when: final_target = nil and carStopInAZebraCrossing = false and carStopInAStop = false {
        current_path <- compute_path(graph: roadsNetwork, target: targetCrossroads);
        if (current_path = nil) {
            numTimesCurrentPathNull <- numTimesCurrentPathNull + 1;
            if (numTimesCurrentPathNull > 10) {
                // Attempt alternative starting positions within search radius
                float search_radius <- radiusDefault;
                list<crossroads> potentialLocations <- crossroads where (distance_to(each.location, self.location) < search_radius and !(each.crossroadsNoInitialLocation)) sort_by (distance_to(each.location, self.location));
                loop initialCrossroadSwitch over: potentialLocations {
                    location <- initialCrossroadSwitch.location;
                    current_path <- compute_path(graph: roadsNetwork, target: targetCrossroads);
                    if (current_path = nil) {
                        list<crossroads> potentialTargets <- crossroads where (distance_to(each.location, self.targetCrossroads.location) < search_radius and !(each.crossroadsNoInitialLocation)) sort_by (distance_to(each.location, targetCrossroads.location));
                        loop targetCrossroadSwitch over: potentialTargets {
                            current_path <- compute_path(graph: roadsNetwork, target: targetCrossroadSwitch);
                            if (current_path != nil) { break; }
                        }
                    }
                    if (current_path != nil) { break; }
                }
            }
        }
    }
    
    // Reflex: Drive along route and handle arrival
    reflex moveNormalCars when: current_path != nil and final_target != nil and carStopInAStop = false and carStopInAZebraCrossing = false and carStopInAYield = false {
        do drive;
        if (final_target != nil) {
            if (real_speed = 0 #km / #h) {
                counterStucked <- counterStucked + step;
                if (counterStucked mod thresholdStucked = 0.0) {
                    proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.2]);
                }
            } else {
                counterStucked <- 0.0;
                proba_use_linked_road <- 0.0;
            }
            do trafficControl;
        } else {
            // Disembark passengers at destination
            loop p over: passengers {
                p.location <- p.the_target.location;
                p.the_target <- nil;
                p.stopped <- true;
            }
            do die;
        }
    }

    // Reflex: Update and calculate CO2 consumption
    reflex updateAndCalculateFuelConsumption when: final_target != nil and calculate_CO2 {
        float consumoStep <- step * 60 * real_speed * (CO2_g_km / 1000) / 1000;
        consumoCO2 <- consumoStep;
    }

    aspect default {
        if (render3D) {
            point loc;
            if (current_road = nil) {
                loc <- location;
            } else {
                float val <- (roads(current_road).lanes - current_lane) + 0.5;
                val <- on_linked_road ? -val : val;
                loc <- (val = 0) ? location : (location + { cos(heading + 90) * val, sin(heading + 90) * val });
            }
            draw rectangle(1, vehicle_length) + triangle(1)
                rotate: heading + 90
                depth: 1 
                color: color 
                at: loc;
            if (breakdown) {
                draw circle(1) at: loc color: color;
            }
        } else {
            if (carsEnhancedAppearance) {
                if (current_road != nil) {
                    point pos <- compute_position();
                    draw rectangle(vehicle_length, lane_width * num_lanes_occupied)
                        at: pos color: rndcolor rotate: heading border: #black;
                    draw triangle(lane_width * num_lanes_occupied) 
                        at: pos color: #white rotate: heading + 90 border: #black;
                }
            } else {
                draw breakdown ? square(8) : triangle(8) color: color rotate: heading + 90;
            }
        }
    }
}

// ElectricCars species (electric autonomous taxis) inheriting from vehicles
species electricCars parent: vehicles {

    /********************************************************
     * Attributes
     ********************************************************/
    rgb color <- #orange;                                   // Main display color for electric cars
    rgb colorShow <- rnd_color(255);                        // Randomized secondary color

    bool carStopInAElectricRecharge <- false;               // Flag for pausing at charging station
    bool lowBattery <- false;                               // Indicates low battery state
    float timeToStopInAElectricRecharge;                    // Duration to recharge at station

    // Battery state and connector
    float soc;                                              // State of Charge (0.0 to 1.0)
    string typeConnector;                                   // Connector type (e.g., CCS2, Type2, ChaDeMo)
    float capacityCnom <- 28.0;                             // Nominal battery capacity in kWh
    float tension <- 360.0;                                 // Battery voltage in V
    float batteryCapacity <- 6.6;                           // Effective battery capacity in kWh
    float efficiency <- 11.5 / 100.0;                       // Energy consumption per km (kWh/km)

    // Current trip info
    Trip currentTrip <- nil;                                // Active trip details

    // Route and charging variables
    crossroads closestChargingPoint;                        // Nearest compatible charging station
    crossroads targetElectricRecharge;                     // Charging station destination
    point saveFinalCrossroads;                              // Saved endpoint for return trips

    // For distance calculations to charging stations
    list<float> distancesToElectricRecharges;               // Distances to all charging stations
    list<crossroads> electricRecharges;                     // List of available charging stations

    int numTimesCurrentPathNull <- 0;                       // Retry counter for pathfinding failures

    // Taxi state flags
    bool isAvailable <- true;                               // Ready to accept rides
    bool isWandering <- true;                               // Currently roaming
    bool rideRequest <- false;                              // Pending ride request
    bool headingToPickUpPassenger <- false;                 // En route to pick up a passenger
    bool headingToChargingPoint <- false;                   // En route to charging station
    bool headingToDropOffPassenger <- false;                // En route to drop off a passenger

    // Passengers awaiting pickup
    list<Person> passengersToPickUp <- [];

    // Percentage of route completed
    float routePercentage <- 0.0;

    /********************************************************
     * Actions
     ********************************************************/
    action initialize {
        right_side_driving <- true;                         // Enforce right-side driving
        if (soc < 0.30) {
            lowBattery <- true;
            do printWarning;
        } else {
            lowBattery <- false;
        }
    }

    action printWarning {
        // Remove non-taxi debug messages
    }

    action printError {
        // Remove non-taxi error messages
    }

    action calculateTaxiFare {
        currentTrip.waitingTime <- currentTrip.pickupTime - currentTrip.requestTime; // Compute waiting time
        currentTrip.tripTime <- int(currentTrip.completionTime - currentTrip.pickupTime); 
        currentTrip.tripCost <- currentTrip.tripTime * 0.05;                       // Calculate fare at €0.05 per unit time
    }

    action drainBattery {
        // Compute state-of-charge reduction based on distance and efficiency
        float socCalc <- (speed*step*efficiency/1000)/capacityCnom;
        float distance <- speed*step;
        float socWaste <- distance/1000*efficiency; 
        soc <- soc - socCalc;
    }

    action v2g {
        // Vehicle-to-grid discharge if V2G is activated
        if V2GActivated {
            float socCalc <- (((efficiency * 100 * 3600) / tension) * (0.5 * (60*step) ^ 2)) / (capacityCnom * 3600);
            soc <- soc - socCalc/100;
        }
    }

    /********************************************************
     * Reflexes
     ********************************************************/
    // Reflex: Electric cars with sufficient battery
    reflex timeToGoElectricCarsWithBattery
    when: lowBattery = false
       and final_target = nil
       and carStopInAElectricRecharge = false
       and carStopInAStop = false
       and carStopInAYield = false
       and carStopInAZebraCrossing = false {
       
       if (soc < 0.30) {
           lowBattery <- true;
           do printWarning;
       } else {
           if (targetCrossroads = nil) {
               targetCrossroads <- one_of(crossroads where !each.crossroadsNoInitialLocation);
           }
           current_path <- compute_path(graph: roadsNetwork, target: targetCrossroads);
           if (current_path = nil) {
               numTimesCurrentPathNull <- numTimesCurrentPathNull + 1;
               if (numTimesCurrentPathNull > 10) {
                   float search_radius <- radiusDefault;
                   list<crossroads> potentialTargets <- crossroads where (
                       distance_to(each.location, targetCrossroads.location) < search_radius and !(each.crossroadsNoInitialLocation)
                   ) sort_by (distance_to(each.location, targetCrossroads.location));
                   loop alt over: potentialTargets {
                       current_path <- compute_path(graph: roadsNetwork, target: alt);
                       if (current_path != nil) { break; }
                   }
                   if (current_path = nil) {
                       list<crossroads> potentialLocations <- crossroads where (
                           distance_to(each.location, self.location) < search_radius and !(each.crossroadsNoInitialLocation)
                       ) sort_by (distance_to(each.location, self.location));
                       loop altLoc over: potentialLocations {
                           location <- altLoc.location;
                           current_path <- compute_path(graph: roadsNetwork, target: targetCrossroads);
                           if (current_path != nil) { break; }
                       }
                   }
               }
           }
       }
    }

    // Reflex: Electric cars with low battery – navigate to charger
    reflex timeToGoElectricCarsWithoutBattery
    when: lowBattery = true
       and final_target = nil
       and headingToChargingPoint = false
       and carStopInAElectricRecharge = false
       and carStopInAStop = false
       and carStopInAYield = false
       and carStopInAZebraCrossing = false {
       
       if (typeConnector = "CCS2") {
           closestChargingPoint <- crossroads where (each.hasCCS2) closest_to self.location;
       } else if (typeConnector = "Type2") {
           closestChargingPoint <- crossroads where (each.hasType2) closest_to self.location;
       } else if (typeConnector = "ChaDeMo") {
           closestChargingPoint <- crossroads where (each.hasChaDeMo) closest_to self.location;
       }
       current_path <- compute_path(graph: roadsNetwork, target: closestChargingPoint);
       if (current_path = nil) {
           numTimesCurrentPathNull <- numTimesCurrentPathNull + 1;
           if (numTimesCurrentPathNull > 3) {
               float search_radius <- radiusDefault;
               list<crossroads> potentialTargets <- crossroads where (
                   distance_to(each.location, closestChargingPoint.location) < search_radius and !(each.crossroadsNoInitialLocation)
               ) sort_by (distance_to(each.location, closestChargingPoint.location));
               loop alt over: potentialTargets {
                   current_path <- compute_path(graph: roadsNetwork, target: alt);
                   if (current_path != nil) { 
                       final_target <- alt;
                       headingToChargingPoint <- true;
                       break;
                   }
               }
               if (current_path = nil) {
                   list<crossroads> potentialLocations <- crossroads where (
                       distance_to(each.location, self.location) < search_radius and !(each.crossroadsNoInitialLocation)
                   ) sort_by (distance_to(each.location, self.location));
                   loop altLoc over: potentialLocations {
                       location <- altLoc.location;
                       current_path <- compute_path(graph: roadsNetwork, target: closestChargingPoint);
                       if (current_path != nil) { 
                           final_target <- closestChargingPoint;
                           headingToChargingPoint <- true;
                           break;
                       }
                   }
               }
           }
       }
       headingToChargingPoint <- true;
       write ""+self+"-1 a free taxi por carga";
       taxiCallCenter.freeTaxis <- taxiCallCenter.freeTaxis - 1; // Update free taxi count
       if (closestChargingPoint != nil) {
           timeToStopInAElectricRecharge <- closestChargingPoint.timeRecharge * 3600; 
       }
       isAvailable <- false;
       isWandering <- false;
       headingToPickUpPassenger <- false;
       headingToDropOffPassenger <- false;
    }

    // Reflex 3: Manage recharging at station
    reflex stopToRecharge
    when: current_path = nil
       and final_target = nil 
       and lowBattery = true
       and carStopInAElectricRecharge = true
       and carStopInAStop = false
       and carStopInAYield = false
       and carStopInAZebraCrossing = false {
       
       self.location <- closestChargingPoint.location;           // Lock position at charger
       contStop <- contStop + step;                              // Increment recharge timer

       // Increment SoC based on charger power
       float socCalc <- (closestChargingPoint.maxPower*closestChargingPoint.maxElectricity*step/3600)/ (capacityCnom);
       soc <- soc + socCalc;

       // Finish charging when time or SoC threshold reached
       if ((contStop >= timeToStopInAElectricRecharge) or (soc >= 0.80)) {
           contStop <- 0.0;
           carStopInAElectricRecharge <- false;
           lowBattery <- false;

           // Reset states to resume roaming
           self.location <- ((crossroads where !each.crossroadsNoInitialLocation) closest_to self.location).location;
           final_target <- nil;
           isAvailable <- true;
           isWandering <- true;
           headingToChargingPoint <- false;
           write ""+self+"+1 a free taxi por fin de carga";
           taxiCallCenter.freeTaxis <- taxiCallCenter.freeTaxis + 1; // Update free taxi count
       }
    }

    // Reflex 4: Normal movement for electric cars on a route
    reflex moveElectricCars
    when: current_path != nil
       and final_target != nil
       and carStopInAStop = false
       and carStopInAYield = false
       and carStopInAZebraCrossing = false {
       
       do drive;          // Perform driving step
       do drainBattery;   // Deplete battery based on movement
       
       // Update route completion percentage
       if (current_path != nil and current_road != nil) {
           routePercentage <- (current_path.edges index_of current_road) / length(current_path.edges);
       }
       
       // Handle ride requests while roaming
       if (isWandering and rideRequest) {
           write "Taxi received a ride request while roaming";
           final_target <- nil;
           current_path <- nil;
           headingToPickUpPassenger <- true;
           isAvailable <- false;
           isWandering <- false;
           rideRequest <- false;
           write ""+self+"-1 a free taxi por recibir cliente";
           taxiCallCenter.freeTaxis <- taxiCallCenter.freeTaxis - 1; // Update free taxi count
       
       } else {
           // Continue towards destination
           if (final_target != nil) {
               // Handle congestion if stuck
               if (real_speed = 0 #km / #h) {
                   counterStucked <- counterStucked + step;
                   if (counterStucked mod thresholdStucked = 0.0) {
                       proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.2]);
                   }
               } else {
                   counterStucked <- 0.0;
                   proba_use_linked_road <- 0.0;
               }
               do trafficControl;
           
           // Arrived or no path to advance
           } else {
               write "Vehicle " + self + " has reached destination: " + final_target;
           
               // Pickup case
               if (headingToPickUpPassenger) {
                   loop p over: passengersToPickUp {
                       passengers <- passengers + p;
                       passengersToPickUp <- passengersToPickUp - p;
                       if (p.the_target != nil) {
                           targetCrossroads <- (crossroads where !each.crossroadsNoInitialLocation) closest_to p.the_target.location;
                           currentTrip.pickupTime <- current_date;
                       }
                   }
                   headingToPickUpPassenger <- false;
                   headingToDropOffPassenger <- true;
                   isAvailable <- false;
                   isWandering <- false;
                   final_target <- nil;
                   current_path <- nil;
           
               // Drop-off case
               } else if (headingToDropOffPassenger) {
                   loop p over: passengers {
                       write "Dropping off passenger: " + p;
                       p.location <- p.the_target.location;
                       p.the_target <- nil;
                       p.stopped <- true;
                       passengers <- passengers - p;
                   }
                   headingToDropOffPassenger <- false;
                   isAvailable <- true;
                   isWandering <- true;
                   final_target <- nil;
                   current_path <- nil;
                   currentTrip.completionTime <- current_date;
                   currentTrip.tripStatus <- "Finalizado";
                   taxiCallCenter.finishedTrips <- taxiCallCenter.finishedTrips + currentTrip;
                   do calculateTaxiFare;
                   currentTrip <- nil;
                   write ""+self+"+1 a free taxi";
                   taxiCallCenter.freeTaxis <- taxiCallCenter.freeTaxis + 1; // Update free taxi count
           
               // Charging arrival case
               } else if (headingToChargingPoint) {
                   write "Arrived at charging station.";
                   headingToChargingPoint <- false;
                   carStopInAElectricRecharge <- true;
           
               // Roaming case
               } else if (isWandering) {
                   targetCrossroads <- one_of(crossroads where !each.crossroadsNoInitialLocation);
                   current_path <- nil;
               }
           }
       }
    }

    /********************************************************
     * Aspect
     ********************************************************/
    aspect default {
        if (render3D) {
            point loc;
            if (current_road = nil) {
                loc <- location;
            } else {
                float val <- (roads(current_road).lanes - current_lane) + 0.5;
                val <- on_linked_road ? -val : val;
                loc <- (val = 0)
                    ? location
                    : (location + { cos(heading + 90) * val, sin(heading + 90) * val });
            }
            draw rectangle(1, vehicle_length) + triangle(1)
                rotate: heading + 90
                depth: 1 
                color: color 
                at: loc;
            if (breakdown) {
                draw circle(1) at: loc color: color;
            }
        } else {
            if (carsEnhancedAppearance and current_road != nil) {
                point pos <- compute_position();
                draw rectangle(vehicle_length, lane_width * num_lanes_occupied)
                    at: pos color: color rotate: heading border: #black;
                draw triangle(lane_width * num_lanes_occupied)
                    at: pos color: #red rotate: heading + 90 border: #black;
            } else {
                draw breakdown ? square(8) : triangle(8) 
                    color: color 
                    rotate: heading + 90;
            }
        }
    }

}
species Person skills: [moving] {

    // Basic inherited variables required to define the person
    string age_range;
    string age_group;
    string gender;
    int age;
    building living_place <- nil;
    building working_place <- nil;
    Household home;
    int start_work;
    int end_work;
    int bedtime;
    int hourIsFree;
    int delayed_start <- rnd(0, 30);
    string objective;
    string workPlaceString;
    building the_target <- nil;           // Current destination (e.g., for activities)
    building the_final_target <- nil;     // Final destination (e.g., for trains)
    string formOfTransportation;
    list<Person> children <- [];
    vehicles assigned_vehicle <- nil;
    Person father <- nil;
    Person mother <- nil;
    Person partner <- nil;
    bool newObjective <- false;
    list<Person> activity_partners <- [];
    bool inActivity <- false;
    bool is_student <- false;
    bool forcedWalkMode <- false;
    bool longDistance <- false;
    bool stopped <- true;

    // Variables specific to walker functionality
    bool isMoving <- false;
    crossroads start;
    crossroads finishPoint;               // Renamed from finishPn
    path current_path;
    bool startJourney <- false;           // Renamed from iniciarSalida
    bool waitingForTrain <- false;
    // Variables for pedestrian crossings
    streets lastEdge;
    crossroads lastNode;
    crossroads stationAgent;
    string stationString;
    bool isCrossing;                       // Renamed from estaCruzando
    crossroads nextNode <- nil;
    int positionCurrentEdge <- 0;
    int cycles;
    int timeToLook <- 5;                   // Time taken to look and cross the zebra crossing
    // Counter for when no route is found in goto
    int nullTTCount <- 0;

    // Initialization: assign attributes based on age and determine initial destinations
    init {
        // Determine if the person works in Leganés (based on probabilities: 0.41 and 0.59)
        bool worksInLeganes <- rnd_choice([true :: 0.41, false :: 0.59]);
        
        // Assign age group and workplace based on age
        if (age <= 5) {
            age_group <- "Toddler";
            working_place <- one_of(building where (each.buildingType = "kindergarten"));
        } else if (age <= 12) {
            age_group <- "Child";
            working_place <- one_of(building where (each.buildingType = "school"));
        } else if (age <= 17) {
            age_group <- "Teen";
            working_place <- one_of(building where (each.buildingType = "school" or each.buildingType = "college"));
        } else if (age <= 30) {
            age_group <- "Young";
            is_student <- rnd_choice([true :: 0.6, false :: 0.4]);
            if (is_student) {
                working_place <- one_of(building where (each.buildingType = "university"));
            } else {
                // Select workplace from commercial/industrial options
                working_place <- building(one_of(building where (
                    each.buildingType = "yes" or each.buildingType = "warehouse" or each.buildingType = "office" or 
                    each.buildingType = "commercial" or each.buildingType = "industrial" or each.buildingType = "government" or 
                    each.buildingType = "hospital" or each.buildingType = "university" or each.buildingType = "school" or 
                    each.buildingType = "retail" or each.buildingType = "college" or each.buildingType = "civic" or 
                    each.leisureType = "fitness_centre" or each.leisureType = "sports_hall" or each.leisureType = "music_venue"
                )));
            }
        } else if (age <= 64) {
            age_group <- "Adult";
            working_place <- building(one_of(building where (
                each.buildingType = "yes" or each.buildingType = "warehouse" or each.buildingType = "office" or 
                each.buildingType = "commercial" or each.buildingType = "industrial" or each.buildingType = "government" or 
                each.buildingType = "hospital" or each.buildingType = "university" or each.buildingType = "school" or 
                each.buildingType = "retail" or each.buildingType = "college" or each.buildingType = "civic" or 
                each.leisureType = "fitness_centre" or each.leisureType = "sports_hall" or each.leisureType = "music_venue"
            )));
        } else {
            age_group <- "Elderly";
            start_work <- 9;
            end_work <- 9;
            working_place <- nil;
        }
       
        // If home is not 'city' type and person is young or adult, update workplace based on Leganés exit probabilities
        if (!(living_place.buildingType = "city") and ((age_group = "Young" and !is_student) or age_group = "Adult")) {
            // Use Leganés exit probabilities (renamed globally to leganesExitProbabilities)
            string leganesExit <- rnd_choice(leganesExitProbabilities);
            map<string, string> city_to_simulation <- [
                "Alcorcón" :: "Alcorcon",
                "Fuenlabrada" :: "Fuenlabrada",
                "Getafe" :: "Getafe norte",
                "Humanes de Madrid" :: "Extremadura",
                "Leganés" :: "Leganés",
                "Madrid" :: "Madrid",
                "Móstoles" :: "Mostoles"
            ];
            leganesExit <- city_to_simulation[leganesExit];
            working_place <- (leganesExit = "Leganés") 
                ? working_place 
                : first(building where (each.buildingType = "city" and each.buildingName = leganesExit));
        }
		
        // Assign name, objective, and initial location
        name <- "Person_" + (index);
        objective <- "resting";
        self.location <- living_place.location;
        home.houseNumber <- "House_" + (index mod 2 + 1);
        if (working_place != nil) {
            workPlaceString <- working_place.buildingType + " leisure:" + working_place.leisureType;
        }
    }

    /////////////////////////////////////////////////////////////
    // Reflex to initiate movement
    // Triggered when a destination (the_target) exists and movement must start.
    /////////////////////////////////////////////////////////////
	reflex motionStarter when: the_target != nil and newObjective {
	    if (age_group != "Elderly") {
	        longDistance <- (living_place.buildingType = "city") or (working_place.buildingType = "city");
	    }
	    
	    // If forced to walk and not a long distance
	    if (forcedWalkMode) and !longDistance {
	        startJourney <- true;
	        newObjective <- false;
	        forcedWalkMode <- false;
	        contadorPeatones <- contadorPeatones + 1;
	    }
	    else {
	    	// Travel between cities
	        if (longDistance) {
	            formOfTransportation <- rnd_choice([
	                "car"   :: carLongDistanceProbability,
	                "train" :: trainLongDistanceProbability,
	                "taxi"  :: taxiLongDistanceProbability
	            ]);	
	            if (formOfTransportation = "train") {
	                list<building> l <- building where (self intersects each and each.buildingType = "city");
	                if (length(l) > 0) { // Outside current simulation area, in another city l[0]
	                    // Board the train
	                    // Map origin cities to their corresponding stations
	                    crossroads station;
	                    // Mapping of cities to their nearest stations
	                    map<string, string> city_to_station <- [
	                        "Mostoles"    :: "Humanes",
	                        "Extremadur"  :: "Humanes",
	                        "Fuenlabrad"  :: "Humanes",
	                        "Alcorcón"    :: "Humanes",
	                        "Madrid"      :: "Madrid",
	                        "Getafe"      :: "Madrid"
	                    ];
	                    string station_name <- city_to_station[l[0].buildingName];
	                    if (station_name != nil) {
	                        // Find the first crossroads matching the station name
	                        station <- first(crossroads where (
	                            each.isTrainStation and each.nameTrainStation = station_name
	                        ));
	                    }
	                    if (station != nil) {
	                        station.waitingPassengers <- station.waitingPassengers + self;
	                        waitingForTrain <- true;
	                    }
	                    // Save final destination and update target to the train station
	                    the_final_target <- the_target;
	                    the_target <- building where (
	                        each.buildingType = "train_station"
	                    ) closest_to the_final_target;
	                }
	                else if (the_target.buildingType = "city") { // Must travel to another city
	                    the_final_target <- the_target;
	                    the_target <- building where (
	                        each.railwayType = "station" or each.railwayType = "platform"
	                    ) closest_to self.location;
	                    startJourney <- true; // Walking to the station
	                    forcedWalkMode <- false;
	                }
	                contadorTrenes <- contadorTrenes + 1;
	            }
	            else if (formOfTransportation = "taxi") {
	                ask taxiSwitchboard {
	                    do requestTaxi(myself);
	                }
	                contadorTaxis <- contadorTaxis + 1;
	            }
	            else if (formOfTransportation = "car") {
	                do instantiate_car;
	                contadorCoches <- contadorCoches + 1;
	            }
	            newObjective <- false;
	        }
	        else {
	        	// Short trips within the city
	            if (the_target = nil) {
	                nullTTCount <- nullTTCount + 1;
	            }
	            // Select mode of transport for short distances
	            formOfTransportation <- rnd_choice([
	                "walking" :: walkShortDistanceProbability,
	                "car"     :: carShortDistanceProbability,
	                "taxi"    :: taxiShortDistanceProbability
	            ]);	
	            if (formOfTransportation = "car") {
	                do instantiate_car;
	                newObjective <- false;
	                contadorCoches <- contadorCoches + 1;
	            }
	            else if (formOfTransportation = "taxi") {
	                ask taxiSwitchboard {
	                    do requestTaxi(myself);
	                }
	                newObjective <- false;
	                contadorTaxis <- contadorTaxis + 1;
	            }
	            else if (formOfTransportation = "walking") {
	                startJourney <- true;
	                newObjective <- false;
	                forcedWalkMode <- false;
	                contadorPeatones <- contadorPeatones + 1;
	            }
	        }
	    }
	}

    /////////////////////////////////////////////////////////////
    // Reflex: prepare the route and start movement
    /////////////////////////////////////////////////////////////
    reflex empezar when: startJourney {
        start <- (crossroads where each.isStreet) closest_to self.location;
        finishPoint <- (crossroads where each.isStreet) closest_to the_target.location;
        current_path <- path_between(streetsNetwork, start, finishPoint);
        startJourney <- false;
        isMoving <- true;
        speed <- self.speed;
        newObjective <- false;
        forcedWalkMode <- false;
        stopped <- false;
    }

    /////////////////////////////////////////////////////////////
    // Reflex: walk the path, handling zebra crossings
    /////////////////////////////////////////////////////////////
    list<geometry> zebra_edges <- [];
    bool waitingToCross <- false;
    crossroads crossingNode;
    crossroads zebraCross;
	reflex walk when: isMoving and finishPoint != nil and (not startJourney) {
	    // Move along the current_path
	    do goto(target: finishPoint, on: streetsNetwork, speed: speed, return_path: true, recompute_path: false);
	    // Get index of current_edge in current_path.edges
	    positionCurrentEdge <- int((current_path = nil) ? nil : current_path.edges index_of current_edge);
	    
	    // 3. Release crossing once passed
	    if (isCrossing) {
	        if (length(self.zebra_edges) > 0 and positionCurrentEdge >= 0) {
	            geometry lastZebraEdge <- last(zebra_edges);
	            int lastZebraEdgeIndex <- current_path.edges index_of lastZebraEdge;
	            if (positionCurrentEdge > lastZebraEdgeIndex) {
	                // Release the zebra crossing block
	                isCrossing <- false;
	                // Clear crossing flags on previous crossing edges
	                loop edge over: zebra_edges {
	                    try {
	                        crossroads lastZebraCrossing <- crossroads(
	                            current_path.vertices[current_path.edges index_of edge]
	                        );
	                        lastZebraCrossing.pedestrianCrossing <- false;
	                    }
	                }
	                // Clear stored zebra edges
	                zebra_edges <- [];
	            }
	        }
	    }
	    
	    // 1. Detect upcoming zebra crossings and store edges
	    if (current_path != nil 
	        and positionCurrentEdge >= 0 
	        and positionCurrentEdge < (length(current_path.edges) - 2)) {
	        
	        loop i from: (positionCurrentEdge + 1) to: (positionCurrentEdge + 2) {
	            zebraCross <- crossroads(current_path.vertices[i]);
	            if (zebraCross.isZebraCrossing) {
	                if (i < length(current_path.edges) and 
	                    !(current_path.edges[i] in self.zebra_edges)) {
	                    self.zebra_edges <- self.zebra_edges + (current_path.edges[i]);
	                }
	            }
	        }
	        
	        // 2. Activate crossing at the next node
	        crossingNode <- crossroads(current_path.vertices[positionCurrentEdge + 1]);
	        if (crossingNode.isZebraCrossing) {
	            isCrossing <- true;
	            crossingNode.pedestrianCrossing <- true;
	        }
	    }
        
        // Arrival at destination
        if (finishPoint.location = self.location) {
            location <- point(the_target);
            isMoving <- false;
            // If using train and arrival at station, enqueue at station
            if (formOfTransportation = "train" 
                and (the_target.railwayType = "station" or the_target.railwayType = "platform")
                and (not waitingForTrain)) {
                stationString <- (the_target.buildingName = "Leganés") 
                    ? "Leganés Central" 
                    : the_target.buildingName + ((the_final_target.buildingName = "Madrid") ? " - Vía 1" : " - Vía 2");
                crossroads station <- one_of(crossroads where (
                    each.isTrainStation and each.nameTrainStation = ((the_target.buildingName = "Leganés") 
                        ? "Leganés Central" 
                        : the_target.buildingName) + ((the_final_target.buildingName = "Madrid" or the_final_target.buildingName = "Getafe") 
                        ? " - Vía 1" 
                        : " - Vía 2")
                ));
                if (station != nil) {
                    station.waitingPassengers <- station.waitingPassengers + self;
                    waitingForTrain <- true;
                }
                stationAgent <- station;
            }
            finishPoint <- nil;
            stopped <- true;
            the_target <- nil;
            
            // Clear any remaining zebra crossings
            loop edge over: zebra_edges {
                crossroads lastZebraCrossing <- crossroads(
                    current_path.vertices[current_path.edges index_of edge]
                );
                lastZebraCrossing.pedestrianCrossing <- false;
            }
        }
    }

    /////////////////////////////////////////////////////////////
    // Reflexes for work, return home, and activities schedules
    /////////////////////////////////////////////////////////////
    reflex time_to_work when: working_place != nil and current_date.hour = start_work and current_date.minute = delayed_start and objective = "resting" and stopped {
        the_target <- working_place;
        objective <- "working";
        newObjective <- true;
    }
    reflex time_to_go_home when: current_date.hour = end_work and current_date.minute = delayed_start and objective = "working" and stopped {
        the_target <- living_place;
        objective <- "resting";
        newObjective <- true;
    }
    reflex come_back_home_after_activity when: inActivity and current_date.hour = hourIsFree and current_date.minute = delayed_start and objective != "resting" and stopped {
        the_target <- living_place;
        objective <- "resting";
        inActivity <- false;
        newObjective <- true;
    }
    
    // Reflex to start activities based on age group
    reflex do_activities when: objective = "resting" and current_date.hour >= end_work and current_date.hour + 1 < bedtime and current_date.hour >= hourIsFree and stopped {
        bool requiresCompanion <- false;
        bool askCompanion <- false;
        inActivity <- true;
        switch age_group {
            match "Toddler" {
                objective <- rnd_choice([
                    "resting"    :: 0.4,
                    "go_for_a_walk" :: 0.2,
                    "go_park"    :: 0.2,
                    "go_doctor"  :: 0.2
                ]);
                requiresCompanion <- true;
            }
            match "Child" {
                objective <- rnd_choice([
                    "resting"         :: 0.4,
                    "go_to_friend_home" :: 0.3,
                    "go_sport"        :: 0.3
                ]);
                askCompanion <- false;
            }
            match "Teen" {
                objective <- rnd_choice([
                    "resting"    :: 0.2,
                    "go_sport"   :: 0.2,
                    "go_shopping":: 0.2,
                    "go_cafe"    :: 0.2,
                    "go_bar"     :: 0.2
                ]);
                askCompanion <- (objective = "go_cafe" or objective = "go_bar");
            }
            match "Young" {
                objective <- rnd_choice([
                    "resting"       :: 0.2,
                    "go_for_a_walk" :: 0.2,
                    "go_shopping"   :: 0.2,
                    "go_cafe"       :: 0.2,
                    "go_bar"        :: 0.2,
                    "go_sport"      :: 0.0
                ]);
                askCompanion <- (objective = "go_cafe" or objective = "go_bar" or objective = "go_for_a_walk");
            }
            match "Adult" {
                objective <- rnd_choice([
                    "resting"       :: 0.4,
                    "go_for_a_walk" :: 0.1,
                    "go_shopping"   :: 0.1,
                    "go_cafe"       :: 0.1,
                    "go_bar"        :: 0.1,
                    "go_supermarket":: 0.1,
                    "go_sport"      :: 0.1
                ]);
                askCompanion <- (objective = "go_cafe" or objective = "go_bar" or objective = "go_for_a_walk");
            }
            match "Elderly" {
                objective <- rnd_choice([
                    "resting"    :: 0.4,
                    "go_doctor"  :: 0.1,
                    "go_cafe"    :: 0.1,
                    "go_for_a_walk" :: 0.1,
                    "go_church"  :: 0.0
                ]);
                askCompanion <- (objective = "go_cafe" or objective = "go_bar" or objective = "go_to_doctor" or objective = "go_for_a_walk");
            }
        }
    
        if (objective = "resting") {
            hourIsFree <- current_date.hour + 1;
            activity_partners <- [];
        } else {
            // Assign destination based on selected activity
            switch objective {
                match "go_for_a_walk" {
                    the_target <- one_of(building where (
                        each.leisureType = "park" or each.leisureType = "garden" or 
                        each.buildingType = "university" or each.buildingType = "detached" or each.buildingType = "terrace"
                    ));
                    forcedWalkMode <- true;
                }
                match "go_park" {
                    the_target <- one_of(building where (
                        each.leisureType = "park" or each.leisureType = "garden" or each.leisureType = "dog_park"
                    ));
                    forcedWalkMode <- true;
                }
                match "go_doctor" {
                    the_target <- one_of(building where (
                        each.buildingType = "hospital" or each.buildingType = "clinic"
                    ));
                }
                match "go_to_friend_home" {
                    the_target <- one_of(building where (
                        each.buildingType = "house" or each.buildingType = "residential" or 
                        each.buildingType = "apartments" or each.buildingType = "dormitory"
                    ));
                }
                match "go_sport" {
                    the_target <- one_of(building where (
                        each.leisureType = "fitness_centre" or each.leisureType = "fitness_station" or 
                        each.leisureType = "sports_centre" or each.leisureType = "sports_hall" or 
                        each.leisureType = "stadium" or each.leisureType = "track" or 
                        each.leisureType = "swimming_pool" or each.buildingType = "sports_centre" or 
                        each.buildingType = "sports_hall" or each.buildingType = "stadium"
                    ));
                }
                match "go_shopping" {
                    the_target <- one_of(building where (
                        each.buildingType = "commercial" or each.buildingType = "retail" or 
                        each.buildingType = "kiosk" or each.buildingType = "warehouse"
                    ));
                }
                match "go_cafe" {
                    the_target <- one_of(building where (
                        each.buildingType = "cafe" or each.buildingType = "restaurant" or 
                        each.buildingType = "public" or each.leisureType = "music_venue"
                    ));
                }
                match "go_bar" {
                    the_target <- one_of(building where (
                        each.buildingType = "bar" or each.buildingType = "pub" or 
                        each.buildingType = "public" or each.leisureType = "music_venue"
                    ));
                }
                match "go_supermarket" {
                    the_target <- one_of(building where (
                        each.buildingType = "supermarket" or each.buildingType = "commercial" or 
                        each.buildingType = "retail"
                    ));
                }
                match "go_church" {
                    the_target <- one_of(building where (each.buildingType = "church"));
                }
                match "go_run_errands" {
                    the_target <- one_of(building where (
                        each.buildingType = "civic" or each.buildingType = "government"
                    ));
                }
            }
            hourIsFree <- current_date.hour + 1;
            // Assign companions if required
            if (requiresCompanion or askCompanion) {
                if (mother != nil and mother.objective = "resting") {
                    mother.objective <- "accompany";
                    mother.the_target <- the_target;
                    mother.hourIsFree <- hourIsFree;
                    mother.newObjective <- true;
                    mother.inActivity <- true;
                    mother.stopped <- false;
                    activity_partners <- activity_partners + mother;
                }
                if (father != nil and father.objective = "resting") {
                    father.objective <- "accompany";
                    father.the_target <- the_target;
                    father.hourIsFree <- hourIsFree;
                    father.newObjective <- true;
                    father.inActivity <- true;
                    father.stopped <- false;
                    activity_partners <- activity_partners + father;
                }
                if (partner != nil and partner.objective = "resting") {
                    partner.objective <- "accompany";
                    partner.the_target <- the_target;
                    inActivity <- true;
                    partner.hourIsFree <- hourIsFree;
                    partner.newObjective <- true;
                    partner.stopped <- false;
                    activity_partners <- activity_partners + partner;
                }
                if (requiresCompanion and length(activity_partners) = 0) {
                    objective <- "resting";
                    inActivity <- true;
                    hourIsFree <- current_date.hour + 1;
                    activity_partners <- [];
                    the_target <- nil;
                    newObjective <- false;
                } else {
                    stopped <- false;
                }
            } else {
                stopped <- false;
            }
        }
    }

    /////////////////////////////////////////////////////////////
    // Action to instantiate a normal car for the agent
    /////////////////////////////////////////////////////////////
    action instantiate_car {
        if (objective != "accompany") {
            create normalCars {
                passengers <- myself.activity_partners;
                initialCrossroad <- (crossroads where !(each.crossroadsNoInitialLocation) at_distance 300 #meters closest_to(myself.location));
                if (initialCrossroad = nil) {
                    initialCrossroad <- (crossroads where !(each.crossroadsNoInitialLocation) closest_to(myself.location));
                }
                targetCrossroads <- (crossroads where !(each.crossroadsNoInitialLocation) at_distance 300 #meters closest_to(myself.the_target));
                if (targetCrossroads = nil) {
                    targetCrossroads <- (crossroads where !(each.crossroadsNoInitialLocation) closest_to(myself.the_target));
                }
                map<string, string> data_vehicle <- one_of(vehicleConsumptionMatrix);
                carModel <- data_vehicle["Marca"] + " " + data_vehicle["Submarca"] + " " + data_vehicle["Version"];
                fuel <- data_vehicle["Combustible"];
                CO2_g_km <- float(data_vehicle["CO2_g_km"]);
                // Driving parameters
                max_acceleration <- 5 / 3.6;
                max_speed <- 120.0 #km / #h;
                proba_block_node <- 0.0;
                proba_lane_change_down <- 0.8 + (rnd(500) / 500);
                proba_lane_change_up <- 0.5 + (rnd(500) / 500);
                proba_respect_priorities <- 1.0 - rnd(200 / 1000);
                proba_respect_stops <- [1.0];
                proba_use_linked_road <- 0.0;
                right_side_driving <- true;
                security_distance_coeff <- 5 / 9 * 3.6 * (1.5 - rnd(1000) / 1000);
                lane_change_limit <- 2;
                speed_coeff <- 1.0 - (rnd(600) / 1000);
                thresholdStucked <- float((1 + rnd(5)) #mn);
                vehicle_length <- rnd(2.5, 4.0) #m;
                probabilityBreakdown <- 0.00001;
                carStopInAZebraCrossing <- false;
                carStopInAYield <- false;
                carStopInAStop <- false;
                self.location <- initialCrossroad.location;
            }
        }
    }

    /////////////////////////////////////////////////////////////
    // Aspect for Person agent
    /////////////////////////////////////////////////////////////
    aspect default {
        if (render3D) {
            draw sphere(2) color: color border: #black;
        } else {
            if (isMoving) {
                draw circle(1) color: #lightgoldenrodyellow border: #black;
            } else {
                draw circle(2) color: #blue at: {location.x + rnd(-0.1, 0.1), location.y + rnd(-0.1, 0.1)};
            }
        }
    }
}

// Species encapsulating information for each trip
species Trip {
    int id;
    Person passenger;
    electricCars assignedTaxi <- nil;
    float tripCost <- 0.0;
    float waitingTime <- 0.0;
    int tripTime;
    building finalObjective;
    // It is assumed that current_date is of the correct type and that p.the_target is the destination location
    date requestTime;
    date pickupTime;
    date completionTime;
    string tripStatus <- "pending";
}

species taxiSwitchboard {
    list<Trip> pendingTrips <- [];
    list<Trip> finishedTrips <- [];
    int freeTaxis <- numberOfElectricCars;
    int tripIDCounter <- 0;
    // Assignment mode: "progressive" or "planned" (default "progressive")
    string assignmentMode <- "progressive";
    
    action requestTaxi(Person p) {
        // Create Trip object for the requested ride
        create Trip returns: ret with: [
            id             :: tripIDCounter,
            passenger      :: p,
            finalObjective :: p.the_target,
            requestTime    :: current_date,
            tripStatus     :: "pending"
        ] {
            myself.tripIDCounter <- myself.tripIDCounter + 1;
        }
        // Add the trip to the pending list
        pendingTrips <- pendingTrips + ret[0];
        write "Se agregó la solicitud del pasajero " + p + " a la lista de viajes pendientes.";
        return true;
    }
    
    // Reflex to assign clients to free taxis
    reflex assignClient when: freeTaxis > 0 {
        // Get list of available taxis: not low battery, marked as isAvailable, and wandering
        list<electricCars> availableTaxis <- electricCars where (
            each.lowBattery = false and each.isAvailable = true and each.isWandering
        );
        if (length(availableTaxis) = 0) {
            write "No hay taxis disponibles en este momento.";
        } else {
            loop t over: availableTaxis {
                if (length(pendingTrips) > 0) {
                    Trip selectedTrip <- nil;
                    // Select pending trip according to assignment mode
                    switch (assignmentMode) {
                        match "progressive" {
                            selectedTrip <- pendingTrips with_min_of (
                                each.passenger.location distance_to t.location
                            );
                        }
                        match "planned" {
                            float bestScore <- 1e30; // Very large initial value
                            loop trip over: pendingTrips {
                                float timeWaiting <- current_date - trip.requestTime;
                                trip.waitingTime <- timeWaiting;
                                float score <- t.location distance_to trip.passenger.location - timeWaiting;
                                if (score < bestScore) {
                                    bestScore <- score;
                                    selectedTrip <- trip;
                                }
                            }
                        }
                        match "SVP" {
                            // list routes <- java_call("com.mycompany.MyJspritWrapper", "solveVRP", [requests, taxiFleet]);
                        }
                    }
                    if (selectedTrip != nil) {
                        // Update taxi to head to passenger location
                        t.targetCrossroads <- (crossroads where !each.crossroadsNoInitialLocation at_distance 200 #meters closest_to selectedTrip.passenger.location);
                        if (t.targetCrossroads = nil) {
                            t.targetCrossroads <- (crossroads where !each.crossroadsNoInitialLocation closest_to selectedTrip.passenger.location);
                        }
                        t.rideRequest <- true;
                        t.isAvailable <- false;
                        t.currentTrip <- selectedTrip;
                        t.passengersToPickUp <- t.passengersToPickUp + selectedTrip.passenger;
                        
                        // Assign taxi to the trip
                        selectedTrip.assignedTaxi <- t;
                        // Update trip status
                        selectedTrip.tripStatus <- "in progress";
                        // Remove trip from pending list
                        pendingTrips <- pendingTrips - selectedTrip;
                        
                        write "Taxi " + t + " asignado a pasajero " + selectedTrip.passenger + " (modo " + assignmentMode + ").";
                    }
                }
            }
        }
    }
}

// Experiment "Leganes" (full version) – configures visualization, simulation, vehicles, buses, transport, and defines outputs
experiment Leganes type: gui {
    // GIS and visualization parameters
    parameter "Display in 2D (true) or 3D (false):" var: render3D category: "Visualization";
    parameter "Show road direction arrows (true) or hide them (false):" var: watchDirections category: "Visualization";
    parameter "Enable enhanced vehicle appearance (true/false):" var: carsEnhancedAppearance category: "Visualization";
    parameter "Show charging station connector labels (true/false):" var: showTextChargingPoints category: "Visualization";
    
    // Simulation step size
    parameter "Simulation step duration (minutes):" var: step <- step min: 0.015 #minutes max: 5 #minutes category: "Simulation";
    
    // Autonomous taxi fleet settings
    parameter "Number of electric taxis:" var: numberOfElectricCars <- 1 min: 0 max: 2000 category: "Autonomous Taxi Fleet";
    parameter "Initial search radius (meters):" var: radiusDefault <- 500.0 min: 500.0 max: 2000.0 category: "Autonomous Taxi Fleet";
    parameter "Enable V2G (true/false):" var: V2GActivated category: "Autonomous Taxi Fleet";
    
    // Short-trip transport probability settings
    parameter "Walking probability:" var: walkShortDistanceProbability <- 0.34+0.34/(0.34+0.48+0.02)*0.16 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Car probability:" var: carShortDistanceProbability <- 0.48+0.48/(0.34+0.48+0.02)*0.16 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Taxi probability:" var: taxiShortDistanceProbability <- 0.02+0.02/(0.34+0.48+0.02)*0.16 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    
    // Long-trip transport probability settings
    parameter "Car probability (long trips):" var: carLongDistanceProbability <- 0.48+0.48/(0.48+0.16+0.02)*0.34 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Train probability (long trips):" var: trainLongDistanceProbability <- 0.16+0.16/(0.48+0.16+0.02)*0.34 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Taxi probability (long trips):" var: taxiLongDistanceProbability <- 0.02+0.02/(0.48+0.16+0.02)*0.34 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    
    // People schedule and speed parameters
    parameter "Earliest work start hour:" var: minWorkStart category: "People" min: 2 max: 8;
    parameter "Latest work start hour:" var: maxWorkStart category: "People" min: 8 max: 12;
    parameter "Earliest work end hour:" var: minWorkEnd category: "People" min: 12 max: 16;
    parameter "Latest work end hour:" var: maxWorkEnd category: "People" min: 16 max: 23;
    parameter "Minimum walking speed (km/h):" var: minSpeed category: "People" min: 0.1 #km/#h;
    parameter "Maximum walking speed (km/h):" var: maxSpeed category: "People" max: 10 #km/#h;
        
    // Experiment initialization
    action _init_ {
        create simulation with: [
            numPeople :: 10000,
            numberOfElectricCars :: 15
        ];
        create datetime_keeper number: 1;
    }
    
    // Outputs: map displays and monitors
    output {
        display Map type: opengl toolbar: #gray background: background_color {
            species railway;
            species train;
            species streets;
            species building aspect: default;
            species roads;
            species crossroads;
            species normalCars aspect: default;
            species electricCars aspect: default;
            species Person;
            
            light #ambient intensity: light_intensity;
            light "sun_light" type: #direction direction: {1,1,-1} intensity: light_intensity;
        }
        
        monitor "Date and Time" value: first(datetime_keeper).current_datetime refresh: every(1 #cycle) color: #green;
        monitor "Pending taxi trips:" value: length(taxiCallCenter.pendingTrips) refresh: every(50/step #cycle) color: #blue;
        monitor "Completed taxi trips:" value: length(taxiCallCenter.finishedTrips) refresh: every(50/step #cycle) color: #blue;
        monitor "Average taxi trip time (min):" value: mean(taxiCallCenter.finishedTrips collect each.tripTime)/60 refresh: every(50/step #cycle) color: #blue;
        monitor "Average taxi waiting time (min):" value: mean(taxiCallCenter.finishedTrips collect each.waitingTime)/60 refresh: every(50/step #cycle) color: #blue;
    }
}


// Experiment "CO2 Study" – focuses on analyzing CO2 consumption
experiment CO2Study type: gui {
    // GIS and visualization parameters
    parameter "Display in 2D (true) or 3D (false):" var: render3D category: "Visualization";
    parameter "Show road direction arrows (true/false):"      var: watchDirections category: "Visualization";
    parameter "Enable enhanced vehicle appearance (true/false):" var: carsEnhancedAppearance category: "Visualization";
    parameter "Show charging station connector labels (true/false):" var: showTextChargingPoints category: "Visualization";
    
    // Simulation time step
    parameter "Simulation step duration (minutes):" var: step <- step min: 0.015 #minutes max: 2 #minutes category: "Simulation";
    
    // Autonomous taxi fleet settings
    parameter "Number of electric taxis:" var: numberOfElectricCars <- 1 min: 0 max: 2000 category: "Autonomous Taxi Fleet";
    parameter "Initial search radius (meters):"   var: radiusDefault <- 500.0 min: 500.0 max: 2000.0 category: "Autonomous Taxi Fleet";
        
    // Short-trip transport probabilities
    parameter "Walking probability:" var: walkShortDistanceProbability <- 0.2 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Car probability:"     var: carShortDistanceProbability   <- 0.6 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Taxi probability:"    var: taxiShortDistanceProbability  <- 0.2 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    
    // Long-trip transport probabilities
    parameter "Car probability (long trips):"   var: carLongDistanceProbability   <- 0.6 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Train probability (long trips):" var: trainLongDistanceProbability <- 0.3 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Taxi probability (long trips):"  var: taxiLongDistanceProbability <- 0.1 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    
    // People schedule and speed parameters
    parameter "Earliest work start hour:" var: minWorkStart category: "People" min: 2 max: 8;
    parameter "Latest work start hour:"   var: maxWorkStart category: "People" min: 8 max: 12;
    parameter "Earliest work end hour:"   var: minWorkEnd category: "People" min: 12 max: 16;
    parameter "Latest work end hour:"     var: maxWorkEnd category: "People" min: 16 max: 23;
    parameter "Minimum walking speed (km/h):" var: minSpeed category: "People" min: 0.1 #km/#h;
    parameter "Maximum walking speed (km/h):" var: maxSpeed category: "People" max: 10 #km/#h;
    
    // Experiment initialization: create simulation and date/time keeper
    action _init_ {
        create simulation with: [
            numPeople :: 10000,
            numberOfElectricCars :: 15
        ];
        create datetime_keeper number: 1;
    }
    
    // Reflex to save the simulation every 100 cycles (with log writes)
    reflex store when: cycle = 100 {
        write "================ START SAVE - " + cycle;
        write "Save of simulation:";
        save simulation to: 'sim.gsim' format: 'gsim';
        write "================ END SAVE - " + cycle;
    }
    
    // Output definitions: map display, CO2 chart, and monitor
    output {
        display Map type: opengl toolbar: #gray background: background_color {
            species railway;
            species train;
            species streets;
            species building;
            species roads;
            species crossroads;
            species normalCars;
            species electricCars;
            species Person;
            
            light #ambient intensity: light_intensity;
            light "sun_light" type: #direction direction: {1,1,-1} intensity: light_intensity;
        }
        
        display CO2Chart {
            chart "CO2 consumption over time" type: series {
                data "Total CO2 (kg) consumed" value: sum(normalCars collect each.consumoCO2) color: #green;
            }
        }
        
        monitor "Date and Time" value: first(datetime_keeper).current_datetime refresh: every(1 #cycle);
    }
}


// Experiment "AgeDistribution" – study of population age distribution
experiment AgeDistribution type: gui {
    // GIS and visualization parameters
    parameter "Display in 2D (true) or 3D (false):"                 var: render3D            category: "Visualization";
    parameter "Show road direction arrows (true/false):"           var: watchDirections     category: "Visualization";
    parameter "Enable enhanced vehicle appearance (true/false):"   var: carsEnhancedAppearance category: "Visualization";
    parameter "Show charging station connector labels (true/false):" var: showTextChargingPoints category: "Visualization";
    
    // Simulation time step
    parameter "Simulation step duration (minutes):"                var: step <- step        min: 0.015 #minutes max: 2 #minutes category: "Simulation";
    
    // Autonomous taxi fleet settings
    parameter "Number of electric taxis:"                          var: numberOfElectricCars <- 1 min: 0 max: 2000      category: "Autonomous Taxi Fleet";
    parameter "Initial search radius (meters):"                    var: radiusDefault      <- 500.0 min: 500.0 max: 2000.0 category: "Autonomous Taxi Fleet";
    
    // Short-trip transport probabilities
    parameter "Walking probability:"                               var: walkShortDistanceProbability <- 0.2 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Car probability:"                                   var: carShortDistanceProbability   <- 0.6 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Taxi probability:"                                  var: taxiShortDistanceProbability  <- 0.2 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    
    // Long-trip transport probabilities
    parameter "Car probability (long trips):"                      var: carLongDistanceProbability   <- 0.6 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Train probability (long trips):"                    var: trainLongDistanceProbability <- 0.3 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    parameter "Taxi probability (long trips):"                     var: taxiLongDistanceProbability  <- 0.1 min: 0.0 max: 1.0 category: "Transportation Probabilities";
    
    // People schedule and speed parameters
    parameter "Earliest hour to start work:"                       var: minWorkStart       category: "People" min: 2 max: 8;
    parameter "Latest hour to start work:"                         var: maxWorkStart       category: "People" min: 8 max: 12;
    parameter "Earliest hour to end work:"                         var: minWorkEnd         category: "People" min: 12 max: 16;
    parameter "Latest hour to end work:"                           var: maxWorkEnd         category: "People" min: 16 max: 23;
    parameter "Minimum walking speed (km/h):"                      var: minSpeed           category: "People" min: 0.1 #km/#h;
    parameter "Maximum walking speed (km/h):"                      var: maxSpeed           category: "People" max: 10 #km/#h;
    
    // Experiment initialization: create simulation and date/time keeper
    action _init_ {
        create simulation with: [
            numPeople :: 100000,
            numberOfElectricCars :: 15
        ];
        create datetime_keeper number: 1;
    }
    
    // Output definitions: map display, pie chart, and monitor
    output {
        display Map type: opengl toolbar: #gray background: background_color {
            species railway;
            species train;
            species streets;
            species building;
            species roads;
            species crossroads;
            species normalCars;
            species electricCars;
            species Person;
            
            light #ambient intensity: light_intensity;
            light "sun_light" type: #direction direction: {1,1,-1} intensity: light_intensity;
        }
        display "Age Distribution" {
            chart "Age Distribution Chart" type: pie {
                datalist age_ranges value: age_counts;
            }
        }
        monitor "Date and Time" value: first(datetime_keeper).current_datetime refresh: every(1 #cycle);
    }
}

