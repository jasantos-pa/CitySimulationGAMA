/**
* Name: LeganÃ©s
* Author: Javier Santos MenÃƒÂ©ndez
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
	int maxWorkStart <- 12;
	int minWorkEnd <- 15;
	int maxWorkEnd <- 22;
	// Non-uniform work schedule distributions (high mass in 6-8, smooth tail to 12)
	map<string, float> workStartHourProbabilities <- [
	    "6" :: 0.14,
	    "7" :: 0.26,
	    "8" :: 0.30,
	    "9" :: 0.15,
	    "10" :: 0.08,
	    "11" :: 0.05,
	    "12" :: 0.02
	];
	// Afternoon return distribution (15-22) with peaks at 16-17
	map<string, float> workEndHourProbabilities <- [
	    "15" :: 0.16,
	    "16" :: 0.24,
	    "17" :: 0.24,
	    "18" :: 0.16,
	    "19" :: 0.10,
	    "20" :: 0.05,
	    "21" :: 0.03,
	    "22" :: 0.02
	];
	// Shift length distribution in hours (used to derive end_work from start_work)
	map<string, float> workDurationHourProbabilities <- [
	    "6" :: 0.03,
	    "7" :: 0.12,
	    "8" :: 0.36,
	    "9" :: 0.30,
	    "10" :: 0.14,
	    "11" :: 0.05
	];
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
	string statisticsCity <- "28074 Leganes";
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
	// Synthetic population pool (generated first from marginals, then consumed while building households)
	list<map<string, string>> populationBlueprintPool <- [];
	map<string, list<map<string, string>>> populationBlueprintBuckets <- map<string, list<map<string, string>>>(map([]));
	int populationBlueprintAvailable <- 0;
	map<string, list<building>> residentialBuildingsByDistrict <- map<string, list<building>>(map([]));
	map<string, building> cityEntryBuildings <- map<string, building>(map([]));
	
	// CO2 emission calculation
	bool calculate_CO2 <- true;
	
	// Taxi call center
	taxiSwitchboard taxiCallCenter <- nil;
	
	// Simulation Logger
	SimulationLogger simLogger <- nil;

	// Population generation logging controls
	bool verbose_population_logs <- false;
	bool verbose_init_entity_logs <- false;
	int population_progress_step <- 500;
	bool parallel_household_postprocessing <- true;
	int parallel_household_postprocessing_threshold <- 250;
	
	// Broken-vehicle removal delay
	float broken_removal_minutes <- 3.0 #mn;
	    
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
	        if (verbose_init_entity_logs) {
	            write "Building ID: " + " Location: " + location + " Shape: " + shape + " Name: " + buildingName + " Type: " + buildingType;
	        }
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

	    create SimulationLogger number: 1 returns: loggers;
	    simLogger <- loggers[0];
	    ask simLogger { do initialize_logs; }
	    
	    create electricCars number: numberOfElectricCars {
	        initialCrossroad <- one_of(crossroads where !(each.crossroadsNoInitialLocation));  // Initial intersection for electric cars.
	        self.location <- initialCrossroad.location;  // Electric car initial location.
	        targetCrossroads <- one_of(crossroads where !(each.crossroadsNoInitialLocation));  // Target intersection for electric car.
	        max_acceleration <- 5 / 3.6;               // Maximum acceleration.
	        max_speed <- 70.0;                       // Maximum speed in km/h.
	        proba_block_node <- 0.0;                 // Node block probability.
	        // MOBIL model parameters (replaces proba_lane_change_down/up in GAMA 2025-06)
	        // politeness <- 0.25 + (rnd(250) / 1000);  // FIXME: Variable not found in GAMA 2025-06
	        // threshold_lc <- 0.2 + (rnd(300) / 1000); // FIXME: Variable not found in GAMA 2025-06
	        proba_respect_priorities <- 1.0 - rnd(200 / 1000);   // Probability to respect priorities.
	        proba_respect_stops <- [1.0];            // Stop respect probability.
	        proba_use_linked_road <- 0.0;            // Linked road usage probability.
	        right_side_driving <- true;              // Right-hand driving.
	        speed_coeff <- 1.0 - (rnd(600) / 1000);  // Speed coefficient.
	        thresholdStucked <- float((1 + rnd(5)) #mn);   // Threshold for being stuck (in minutes).
	        vehicle_length <- rnd(2.5, 4.0);         // Vehicle length in meters.
	        probabilityBreakdown <- 0.000005;        // Breakdown probability (reduced to half to prevent deadlocks).
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
    do rebuild_building_lookup_indexes;

    write("Population generation started. Target people: " + numPeople + ", progress step: " + population_progress_step);
    
    // Number of each household type
    int numHouseholds <- createFamilies(0);
    write("Population generation finished. People: " + length(Person) + ", households: " + numHouseholds);
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
	if (simLogger != nil) {
	    ask simLogger { do snapshot_population_and_reference; }
	}
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
    ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â      ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â 
	ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
	ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
	ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
	ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
    
    This module of the code defines the logic that generates the people in the simulation and their characteristics.
    */
    
    
	string normalize_gender_label(string raw_gender) {
    if (raw_gender = nil) { return "female"; }
    string g <- lower_case(raw_gender);
    // Check female variants first: "female" contains the substring "male".
    if (g = "female" or g contains "fem" or g contains "muj") { return "female"; }
    if (g = "male" or g contains "hom" or g contains "varon") { return "male"; }
    if (g contains "male" and !(g contains "female")) { return "male"; }
    return "female";
}

string normalize_household_size_label(string raw_label) {
    if (raw_label = nil) { return nil; }
    string s <- lower_case(raw_label);
    if (s contains "total") { return nil; }
    if (s contains "1") { return "1 persona"; }
    if (s contains "2") { return "2 personas"; }
    if (s contains "3") { return "3 personas"; }
    if (s contains "4") { return "4 personas"; }
    if (s contains "5") { return "5 o mas personas"; }
    return nil;
}

int household_size_from_label(string label) {
    if (label = "1 persona") { return 1; }
    if (label = "2 personas") { return 2; }
    if (label = "3 personas") { return 3; }
    if (label = "4 personas") { return 4; }
    return 5;
}

string household_label_from_size(int hh_size) {
    if (hh_size <= 1) { return "1 persona"; }
    if (hh_size = 2) { return "2 personas"; }
    if (hh_size = 3) { return "3 personas"; }
    if (hh_size = 4) { return "4 personas"; }
    return "5 o mas personas";
}

action rebuild_building_lookup_indexes {
    residentialBuildingsByDistrict <- map<string, list<building>>(map([]));
    cityEntryBuildings <- map<string, building>(map([]));

    loop b over: residential_buildings {
        string district_name <- (b.district = nil) ? "" : (b.district as string);
        if (district_name != "") {
            list<building> district_buildings <- residentialBuildingsByDistrict[district_name];
            if (district_buildings = nil) { district_buildings <- []; }
            district_buildings <- district_buildings + [b];
            residentialBuildingsByDistrict[district_name] <- district_buildings;
        }
    }

    loop b over: (building where (each.buildingType = "city")) {
        string city_name <- (b.buildingName = nil) ? "" : (b.buildingName as string);
        if (city_name != "" and cityEntryBuildings[city_name] = nil) {
            cityEntryBuildings[city_name] <- b;
        }
    }
}

string blueprint_bucket_key(string gender_label, string age_range_label) {
    string g <- normalize_gender_label(gender_label);
    string ar <- age_range_label;
    if (ar = nil or ar = "" or !(ar in age_ranges)) { ar <- age_ranges[0]; }
    return g + "|" + ar;
}

action rebuild_population_blueprint_index {
    populationBlueprintBuckets <- map<string, list<map<string, string>>>(map([]));
    populationBlueprintAvailable <- 0;

    loop bp over: populationBlueprintPool {
        if (bp != nil) {
            string bp_gender <- (bp["gender"] = nil) ? "female" : normalize_gender_label(bp["gender"] as string);
            string bp_age <- (bp["age_range"] = nil) ? age_ranges[0] : (bp["age_range"] as string);
            string key <- blueprint_bucket_key(bp_gender, bp_age);
            list<map<string, string>> bucket <- populationBlueprintBuckets[key];
            if (bucket = nil) { bucket <- []; }
            bucket <- bucket + [bp];
            populationBlueprintBuckets[key] <- bucket;
            populationBlueprintAvailable <- populationBlueprintAvailable + 1;
        }
    }
}

list<string> collect_intersecting_age_ranges(int minAge, int maxAge) {
    list<string> matching <- [];
    loop ar over: age_ranges {
        if (age_range_intersects_bounds(ar, minAge, maxAge)) {
            matching <- matching + [ar];
        }
    }
    if (empty(matching)) {
        matching <- list<string>(age_ranges);
    }
    return matching;
}

list<string> build_blueprint_bucket_keys(list<string> genders, list<string> ranges) {
    list<string> keys <- [];
    loop g over: genders {
        string normalized_gender <- normalize_gender_label(g);
        loop ar over: ranges {
            string key <- blueprint_bucket_key(normalized_gender, ar);
            list<map<string, string>> bucket <- populationBlueprintBuckets[key];
            if (bucket != nil and !empty(bucket)) {
                keys <- keys + [key];
            }
        }
    }
    return keys;
}

map<string, string> pop_blueprint_from_bucket_keys(list<string> bucket_keys) {
    if (bucket_keys = nil or empty(bucket_keys)) { return nil; }

    int total_candidates <- 0;
    loop key over: bucket_keys {
        list<map<string, string>> bucket <- populationBlueprintBuckets[key];
        if (bucket != nil and !empty(bucket)) {
            total_candidates <- total_candidates + length(bucket);
        }
    }
    if (total_candidates <= 0) { return nil; }

    int selected_position <- rnd(1, total_candidates, 1);
    int cumulative <- 0;
    string selected_key <- nil;
    loop key over: bucket_keys {
        list<map<string, string>> bucket <- populationBlueprintBuckets[key];
        int bucket_size <- (bucket = nil) ? 0 : length(bucket);
        if (bucket_size > 0) {
            cumulative <- cumulative + bucket_size;
            if (selected_key = nil and selected_position <= cumulative) {
                selected_key <- key;
            }
        }
    }
    if (selected_key = nil) { return nil; }

    list<map<string, string>> selected_bucket <- populationBlueprintBuckets[selected_key];
    if (selected_bucket = nil or empty(selected_bucket)) { return nil; }

    map<string, string> chosen <- one_of(selected_bucket);
    selected_bucket <- selected_bucket - chosen;
    populationBlueprintBuckets[selected_key] <- selected_bucket;
    populationBlueprintAvailable <- max(0, populationBlueprintAvailable - 1);
    return chosen;
}

map<string, float> canonical_gender_probabilities(map raw_probs) {
    map<string, float> cleaned <- map<string, float>(map(["male" :: 0.0, "female" :: 0.0]));
    if (raw_probs = nil) {
        return map<string, float>(map(["male" :: 0.5, "female" :: 0.5]));
    }
    if (empty(keys(raw_probs))) {
        return map<string, float>(map(["male" :: 0.5, "female" :: 0.5]));
    }
    loop k over: keys(raw_probs) {
        string g <- normalize_gender_label(k);
        float prob <- (raw_probs[k] as float);
        cleaned[g] <- cleaned[g] + prob;
    }
    float s <- cleaned["male"] + cleaned["female"];
    if (s <= 0.0) { return map<string, float>(map(["male" :: 0.5, "female" :: 0.5])); }
    cleaned["male"] <- cleaned["male"] / s;
    cleaned["female"] <- cleaned["female"] / s;
    return cleaned;
}

map<string, float> canonical_household_size_probabilities(map raw_probs) {
    map<string, float> cleaned <- map<string, float>(map([
        "1 persona" :: 0.0,
        "2 personas" :: 0.0,
        "3 personas" :: 0.0,
        "4 personas" :: 0.0,
        "5 o mas personas" :: 0.0
    ]));
    if (raw_probs = nil) {
        return map<string, float>(map([
            "1 persona" :: 0.2,
            "2 personas" :: 0.2,
            "3 personas" :: 0.2,
            "4 personas" :: 0.2,
            "5 o mas personas" :: 0.2
        ]));
    }
    if (empty(keys(raw_probs))) {
        return map<string, float>(map([
            "1 persona" :: 0.2,
            "2 personas" :: 0.2,
            "3 personas" :: 0.2,
            "4 personas" :: 0.2,
            "5 o mas personas" :: 0.2
        ]));
    }
    loop k over: keys(raw_probs) {
        string label <- normalize_household_size_label(k);
        if (label != nil) {
            float prob <- (raw_probs[k] as float);
            cleaned[label] <- cleaned[label] + max(0.0, prob);
        }
    }
    float s <- 0.0;
    loop label over: keys(cleaned) { s <- s + cleaned[label]; }
    if (s <= 0.0) {
        return map<string, float>(map([
            "1 persona" :: 0.2,
            "2 personas" :: 0.2,
            "3 personas" :: 0.2,
            "4 personas" :: 0.2,
            "5 o mas personas" :: 0.2
        ]));
    }
    loop label over: keys(cleaned) { cleaned[label] <- cleaned[label] / s; }
    return cleaned;
}

map<string, float> canonical_household_type_probabilities(map<string, float> raw_probs) {
    map<string, float> cleaned <- map<string, float>(map([]));
    if (raw_probs = nil or empty(keys(raw_probs))) { return cleaned; }
    loop k over: keys(raw_probs) {
        string key_s <- (k = nil) ? "" : (k as string);
        if (key_s != "" and !(lower_case(key_s) contains "total")) {
            float prob <- max(0.0, raw_probs[key_s] as float);
            if (prob > 0.0) { cleaned[key_s] <- prob; }
        }
    }
    float s <- 0.0;
    loop k over: keys(cleaned) { s <- s + cleaned[k]; }
    if (s <= 0.0) { return map<string, float>(map([])); }
    loop k over: keys(cleaned) { cleaned[k] <- cleaned[k] / s; }
    return cleaned;
}

map<string, int> largest_remainder_counts(map<string, float> probs, list<string> categories, int total_count) {
    map<string, int> counts <- map<string, int>(map([]));
    map<string, float> remainders <- map<string, float>(map([]));
    float prob_sum <- 0.0;
    loop c over: categories {
        float p <- (probs[c] = nil) ? 0.0 : max(0.0, probs[c]);
        prob_sum <- prob_sum + p;
    }
    if (prob_sum <= 0.0) { prob_sum <- length(categories); }
    int assigned <- 0;
    loop c over: categories {
        float p <- (probs[c] = nil) ? 0.0 : max(0.0, probs[c]);
        if (prob_sum = length(categories)) { p <- 1.0; }
        float raw_count <- (total_count * p) / prob_sum;
        int base_count <- floor(raw_count);
        counts[c] <- base_count;
        remainders[c] <- raw_count - base_count;
        assigned <- assigned + base_count;
    }
    int remaining <- total_count - assigned;
    loop while: remaining > 0 {
        string best <- categories with_max_of (remainders[each]);
        counts[best] <- counts[best] + 1;
        remainders[best] <- -1.0;
        remaining <- remaining - 1;
    }
    return counts;
}

list<string> build_household_type_plan(map<string, float> raw_probs, int target_households, string fallback_type) {
    list<string> plan <- [];
    if (target_households <= 0) { return plan; }

    map<string, float> probs <- canonical_household_type_probabilities(raw_probs);
    if (empty(keys(probs))) {
        loop i from: 1 to: target_households { plan <- plan + fallback_type; }
        return plan;
    }

    list<string> categories <- [];
    loop k over: keys(probs) { categories <- categories + k; }
    map<string, int> counts <- largest_remainder_counts(probs, categories, target_households);
    loop c over: categories {
        loop i from: 1 to: counts[c] { plan <- plan + c; }
    }

    loop while: length(plan) < target_households { plan <- plan + fallback_type; }
    return shuffle(plan);
}

string sample_household_type_by_size(int household_size) {
    string selected <- "";
    if (household_size = 1) {
        map<string, float> probs <- canonical_household_type_probabilities(householdStructureProbabilities1Person);
        if (!empty(keys(probs))) { selected <- rnd_choice(probs); }
    } else if (household_size = 2) {
        map<string, float> probs <- canonical_household_type_probabilities(householdStructureProbabilities2Persons);
        if (!empty(keys(probs))) { selected <- rnd_choice(probs); }
    } else if (household_size = 3) {
        map<string, float> probs <- canonical_household_type_probabilities(householdStructureProbabilities3Persons);
        if (!empty(keys(probs))) { selected <- rnd_choice(probs); }
    } else if (household_size = 4) {
        map<string, float> probs <- canonical_household_type_probabilities(householdStructureProbabilities4Persons);
        if (!empty(keys(probs))) { selected <- rnd_choice(probs); }
    } else if (household_size >= 5) {
        map<string, float> probs <- canonical_household_type_probabilities(householdStructureProbabilities5Persons);
        if (!empty(keys(probs))) { selected <- rnd_choice(probs); }
    }
    if (selected = nil or selected = "") { selected <- "synthetic_household_size_" + household_size; }
    return selected;
}

Person create_person_from_spec(string gender_label, string age_range_label, Household household) {
    string normalized_gender <- normalize_gender_label(gender_label);
    list<string> age_parts <- split_with(age_range_label, "-");
    int age_min <- age_parts[0] as_int 10;
    int age_max <- age_parts[1] as_int 10;
    if (age_max < age_min) { age_max <- age_min; }
    int age_value <- rnd(age_min, age_max, 1);

    int selectedIndex <- age_ranges index_of age_range_label;
    if (selectedIndex >= 0) { age_counts[selectedIndex] <- age_counts[selectedIndex] + 1; }

    int startWork <- sample_hour_from_probabilities(workStartHourProbabilities);
    if (startWork < minWorkStart) { startWork <- minWorkStart; }
    if (startWork > maxWorkStart) { startWork <- maxWorkStart; }
    int endWork <- sample_end_hour_for_start(startWork);
    int hoursSleep <- rnd(7, 9);
    int calculatedBedtime <- (startWork - hoursSleep) > 0
        ? (startWork - hoursSleep)
        : (24 + (startWork - hoursSleep));

    float speedValue <- rnd(minSpeed, maxSpeed);
    building livingPlace <- household.house;
    building workingPlace <- nil;
    create Person with: [
        age_range    :: age_range_label,
        gender       :: normalized_gender,
        age          :: age_value,
        start_work   :: startWork,
        end_work     :: endWork,
        speed        :: speedValue,
        living_place :: livingPlace,
        working_place:: workingPlace,
        bedtime      :: calculatedBedtime
    ] returns: ret;
    return ret[0];
}

map<string, float> canonical_age_range_probabilities(map raw_probs) {
    map<string, float> cleaned <- map<string, float>(map([]));
    loop ar over: age_ranges { cleaned[ar] <- 0.0; }
    if (raw_probs = nil or empty(keys(raw_probs))) {
        float uniform_prob <- 1.0 / max(1, length(age_ranges));
        loop ar over: age_ranges { cleaned[ar] <- uniform_prob; }
        return cleaned;
    }
    loop k over: keys(raw_probs) {
        string ar <- (k = nil) ? "" : (k as string);
        if (ar in age_ranges) {
            float p <- max(0.0, raw_probs[k] as float);
            cleaned[ar] <- cleaned[ar] + p;
        }
    }
    float s <- 0.0;
    loop ar over: age_ranges { s <- s + cleaned[ar]; }
    if (s <= 0.0) {
        float uniform_prob <- 1.0 / max(1, length(age_ranges));
        loop ar over: age_ranges { cleaned[ar] <- uniform_prob; }
        return cleaned;
    }
    loop ar over: age_ranges { cleaned[ar] <- cleaned[ar] / s; }
    return cleaned;
}

list<map<string, string>> build_population_blueprint_pool(int target_people) {
    list<map<string, string>> pool <- [];
    if (target_people <= 0) { return pool; }

    map<string, float> age_probs <- canonical_age_range_probabilities(ageGroupProbabilities);
    map<string, float> gender_probs <- canonical_gender_probabilities(sexProbabilities);
    sexProbabilities <- gender_probs;

    map<string, int> age_counts_target <- largest_remainder_counts(age_probs, age_ranges, target_people);
    list<string> gender_categories <- ["male", "female"];
    map<string, int> gender_counts_target <- largest_remainder_counts(gender_probs, gender_categories, target_people);

    list<string> age_plan <- [];
    loop ar over: age_ranges {
        loop i from: 1 to: age_counts_target[ar] { age_plan <- age_plan + ar; }
    }
    loop while: length(age_plan) < target_people { age_plan <- age_plan + rnd_choice(age_probs); }
    age_plan <- shuffle(age_plan);

    list<string> gender_plan <- [];
    loop g over: gender_categories {
        loop i from: 1 to: gender_counts_target[g] { gender_plan <- gender_plan + g; }
    }
    loop while: length(gender_plan) < target_people { gender_plan <- gender_plan + rnd_choice(gender_probs); }
    gender_plan <- shuffle(gender_plan);

    loop i from: 0 to: (target_people - 1) {
        pool <- pool + [
            map<string, string>(map([
                "uid" :: ("bp_" + i),
                "age_range" :: age_plan[i],
                "gender" :: gender_plan[i]
            ]))
        ];
    }
    return pool;
}

bool age_range_intersects_bounds(string age_range_label, int minAge, int maxAge) {
    if (age_range_label = nil or age_range_label = "") { return true; }
    list<string> parts <- split_with(age_range_label, "-");
    if (length(parts) < 2) { return true; }
    int lo <- parts[0] as_int 10;
    int hi <- parts[1] as_int 10;
    return !(hi < minAge or lo > maxAge);
}

map<string, string> pull_population_blueprint(string requested_gender, int minAge, int maxAge) {
    if (populationBlueprintAvailable <= 0) { return nil; }
    if (populationBlueprintBuckets = nil or empty(keys(populationBlueprintBuckets))) {
        do rebuild_population_blueprint_index;
    }

    string requested <- (requested_gender = nil or requested_gender = "") ? "" : normalize_gender_label(requested_gender);
    list<string> age_candidates <- collect_intersecting_age_ranges(minAge, maxAge);
    map<string, string> chosen <- nil;

    if (requested != "") {
        list<string> exact_keys <- build_blueprint_bucket_keys([requested], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(exact_keys);
    }
    if (chosen = nil) {
        list<string> age_only_keys <- build_blueprint_bucket_keys(["male", "female"], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(age_only_keys);
    }
    if (chosen = nil and requested != "") {
        list<string> gender_only_keys <- build_blueprint_bucket_keys([requested], age_ranges);
        chosen <- pop_blueprint_from_bucket_keys(gender_only_keys);
    }
    if (chosen = nil) {
        list<string> any_keys <- build_blueprint_bucket_keys(["male", "female"], age_ranges);
        chosen <- pop_blueprint_from_bucket_keys(any_keys);
    }

    return chosen;
}

Person matchPartner(Person partner, Household household) {
    string orientation <- rnd_choice(orientationProbabilities);
    string normalized_partner_gender <- normalize_gender_label(partner.gender);
    string sex <- (orientation = "heterosexual")
        ? ((normalized_partner_gender = "male") ? "female" : "male")
        : normalized_partner_gender;
    string partnerAgeRange <- partner.age_range;
    if ((split_with(partnerAgeRange, "-")[0] as_int 10) >= 60) { partnerAgeRange <- "60-99"; }
    map<string, float> partnerProbabilities <- (normalized_partner_gender = "male")
        ? husbandAgeCoupleProbabilities[partnerAgeRange]
        : wifeAgeCoupleProbabilities[partnerAgeRange];
    string selectedAgeRange <- rnd_choice(partnerProbabilities);
    list<string> ageParts <- split_with(selectedAgeRange, "-");
    int minAge <- ageParts[0] as_int 10;
    int maxAge <- ageParts[1] as_int 10;
    Person newPartner <- getPerson(sex, minAge, maxAge, nil, "", household, false);
    newPartner.partner <- partner;
    partner.partner <- newPartner;
    return newPartner;
}

list<Person> infer_household_core_members(string household_type_label, list<Person> members) {
    list<Person> core <- [];
    if (members = nil or empty(members)) { return core; }
    string ht <- lower_case(household_type_label as string);
    bool is_single_parent <- ht contains "progenitor";
    bool is_couple <- ht contains "pareja";
    bool has_children <- ht contains "hijo";
    bool has_other_persons <- ht contains "otra";

    if (is_single_parent or (is_couple and has_children) or has_other_persons) {
        loop p over: members {
            bool is_parent <- (p.children != nil and !empty(p.children));
            bool is_child <- (p.father != nil or p.mother != nil);
            if ((is_parent or is_child) and !(p in core)) { core <- core + p; }
        }
        // Keep both partners if one of them belongs to the core.
        loop p over: members {
            if (p.partner != nil and (p.partner in core) and !(p in core)) { core <- core + p; }
        }
    }

    if (empty(core) and is_couple) {
        loop p over: members {
            if (p.partner != nil and !(p in core)) { core <- core + p; }
        }
    }

    // Single-person structures: keep one representative.
    if (empty(core) and (ht contains "solo" or ht contains "sola")) { core <- [members[0]]; }
    if (empty(core)) { core <- list<Person>(members); }
    return core;
}

list<Person> enforce_household_relationships(string household_type_label, list<Person> members) {
    if (members = nil or empty(members)) { return members; }

    string ht <- lower_case(household_type_label as string);
    bool is_single_parent <- ht contains "progenitor";
    bool is_couple <- ht contains "pareja";
    bool has_children <- ht contains "hijo";

    // Keep all cohabitants in the same residence.
    building shared_home <- nil;
    loop p over: members {
        if (shared_home = nil and p.living_place != nil) { shared_home <- p.living_place; }
    }
    if (shared_home != nil) {
        loop p over: members { p.living_place <- shared_home; }
    }

    // Remove out-of-household children references to keep links consistent.
    loop p over: members {
        if (p.children != nil and !empty(p.children)) {
            list<Person> cleaned_children <- [];
            loop c over: p.children {
                if (c != nil and (c in members) and !(c in cleaned_children)) {
                    cleaned_children <- cleaned_children + c;
                }
            }
            p.children <- cleaned_children;
        }
    }

    list<Person> children_in_household <- [];
    loop p over: members {
        if (p.children != nil and !empty(p.children)) {
            loop c over: p.children {
                if (c != nil and (c in members) and !(c in children_in_household)) {
                    children_in_household <- children_in_household + c;
                }
            }
        }
    }

    if (empty(children_in_household) and has_children) {
        // Fallback: in couple/single-parent households, non-partner members are children.
        loop p over: members {
            bool is_partnered_adult <- (p.partner != nil and (p.partner in members));
            if (!is_partnered_adult and !(p in children_in_household)) {
                children_in_household <- children_in_household + p;
            }
        }
    }

    if (is_couple and has_children and !empty(children_in_household)) {
        Person parent1 <- nil;
        Person parent2 <- nil;
        loop p over: members {
            if (p.partner != nil and (p.partner in members) and parent1 = nil) {
                parent1 <- p;
            }
        }
        if (parent1 != nil and parent1.partner != nil and (parent1.partner in members)) {
            parent2 <- parent1.partner;
        } else {
            loop p over: members {
                if (p.partner != nil and (p.partner in members) and p != parent1 and parent2 = nil) {
                    parent2 <- p;
                }
            }
        }

        if (parent1 != nil and parent2 != nil and parent1 != parent2) {
            parent1.partner <- parent2;
            parent2.partner <- parent1;
            if (parent1.children = nil) { parent1.children <- []; }
            if (parent2.children = nil) { parent2.children <- []; }

            loop child over: children_in_household {
                if (parent1.gender = "male") {
                    if (child.father = nil) { child.father <- parent1; }
                    else if (child.mother = nil) { child.mother <- parent1; }
                } else {
                    if (child.mother = nil) { child.mother <- parent1; }
                    else if (child.father = nil) { child.father <- parent1; }
                }

                if (parent2.gender = "male") {
                    if (child.father = nil) { child.father <- parent2; }
                    else if (child.mother = nil) { child.mother <- parent2; }
                } else {
                    if (child.mother = nil) { child.mother <- parent2; }
                    else if (child.father = nil) { child.father <- parent2; }
                }

                if (!(child in parent1.children)) { parent1.children <- parent1.children + child; }
                if (!(child in parent2.children)) { parent2.children <- parent2.children + child; }
            }
        }
    }

    if (is_single_parent and !empty(children_in_household)) {
        Person parent <- nil;
        loop p over: members {
            if (parent = nil and p.children != nil and !empty(p.children)) { parent <- p; }
        }
        if (parent = nil) { parent <- one_of(members where (each.age >= 18)); }
        if (parent = nil) { parent <- members[0]; }
        if (parent.children = nil) { parent.children <- []; }

        loop child over: children_in_household {
            if (parent.gender = "male") {
                child.father <- parent;
                child.mother <- nil;
            } else {
                child.mother <- parent;
                child.father <- nil;
            }
            if (!(child in parent.children)) { parent.children <- parent.children + child; }
        }
    }

    loop child over: children_in_household {
        if (child.father != nil and !(child.father in members)) { child.father <- nil; }
        if (child.mother != nil and !(child.mother in members)) { child.mother <- nil; }
    }

    return members;
}

int createFamilies(int s) {
    list<string> household_categories <- ["1 persona", "2 personas", "3 personas", "4 personas", "5 o mas personas"];
    map<string, float> hh_probs <- canonical_household_size_probabilities(householdStructureProbabilities);
    map<string, float> gender_probs <- canonical_gender_probabilities(sexProbabilities);
    sexProbabilities <- gender_probs;
    populationBlueprintPool <- build_population_blueprint_pool(numPeople);
    do rebuild_population_blueprint_index;
    if (verbose_population_logs) {
        write("Population blueprint pool initialized: " + length(populationBlueprintPool)
            + " candidates, indexed available: " + populationBlueprintAvailable);
    }

    float expected_household_size <- 0.0;
    loop cat over: household_categories {
        expected_household_size <- expected_household_size + hh_probs[cat] * household_size_from_label(cat);
    }
    if (expected_household_size <= 0.0) { expected_household_size <- 2.5; }
    int estimated_households <- max(1, round(numPeople / expected_household_size));
    map<string, int> household_counts <- largest_remainder_counts(hh_probs, household_categories, estimated_households);

    int planned_people <- 0;
    loop cat over: household_categories {
        planned_people <- planned_people + household_counts[cat] * household_size_from_label(cat);
    }
    int safe_guard <- 0;
    loop while: planned_people < numPeople and safe_guard < 10000 {
        int missing <- numPeople - planned_people;
        int add_size <- (missing >= 5) ? 5 : missing;
        string add_label <- household_label_from_size(add_size);
        household_counts[add_label] <- household_counts[add_label] + 1;
        planned_people <- planned_people + add_size;
        safe_guard <- safe_guard + 1;
    }
    loop while: planned_people > numPeople and safe_guard < 20000 {
        int excess <- planned_people - numPeople;
        bool fixed <- false;
        loop cat over: ["5 o mas personas", "4 personas", "3 personas", "2 personas", "1 persona"] {
            int sz <- household_size_from_label(cat);
            if (!fixed and sz <= excess and household_counts[cat] > 0) {
                household_counts[cat] <- household_counts[cat] - 1;
                planned_people <- planned_people - sz;
                fixed <- true;
            }
        }
        if (!fixed) {
            loop cat over: ["5 o mas personas", "4 personas", "3 personas", "2 personas"] {
                int sz <- household_size_from_label(cat);
                if (!fixed and household_counts[cat] > 0 and sz > 1) {
                    int reduce <- min(excess, sz - 1);
                    household_counts[cat] <- household_counts[cat] - 1;
                    string down_label <- household_label_from_size(sz - reduce);
                    household_counts[down_label] <- household_counts[down_label] + 1;
                    planned_people <- planned_people - reduce;
                    fixed <- true;
                }
            }
        }
        if (!fixed) { break; }
        safe_guard <- safe_guard + 1;
    }

    list<int> household_plan <- [];
    loop cat over: household_categories {
        loop i from: 1 to: household_counts[cat] {
            household_plan <- household_plan + household_size_from_label(cat);
        }
    }
    household_plan <- shuffle(household_plan);
    
    list<string> type_plan_1 <- build_household_type_plan(
        householdStructureProbabilities1Person,
        household_counts["1 persona"],
        "Otro tipo de hogar"
    );
    list<string> type_plan_2 <- build_household_type_plan(
        householdStructureProbabilities2Persons,
        household_counts["2 personas"],
        "Otro tipo de hogar"
    );
    list<string> type_plan_3 <- build_household_type_plan(
        householdStructureProbabilities3Persons,
        household_counts["3 personas"],
        "Otro tipo de hogar"
    );
    list<string> type_plan_4 <- build_household_type_plan(
        householdStructureProbabilities4Persons,
        household_counts["4 personas"],
        "Otro tipo de hogar"
    );
    list<string> type_plan_5p <- build_household_type_plan(
        householdStructureProbabilities5Persons,
        household_counts["5 o mas personas"],
        "Otro tipo de hogar"
    );
    int type_cursor_1 <- 0;
    int type_cursor_2 <- 0;
    int type_cursor_3 <- 0;
    int type_cursor_4 <- 0;
    int type_cursor_5p <- 0;

    int generated_households <- 0;
    int progress_interval <- max(1, population_progress_step);
    int next_progress <- progress_interval;
    households <- [];
    loop hh_size over: household_plan {
        int hh_size_i <- int(hh_size);
        string numMembers <- household_label_from_size(hh_size_i);
        if (length(Person) >= numPeople) { break; }
        create Household number: 1 returns: household {
            numberPersons <- numMembers;
            string householdDistrict <- rnd_choice(districtDistributionProbabilities);
            list<building> district_houses <- residentialBuildingsByDistrict[householdDistrict];
            if (district_houses != nil and !empty(district_houses)) {
                house <- one_of(district_houses);
            } else {
                house <- one_of(residential_buildings where (each.district = householdDistrict));
            }
            district <- householdDistrict;
            if (house = nil) { dataCSV <- dataCSV + string(self); }
            bool livesInLeganes <- rnd_choice([true :: 0.59, false :: 0.41]);
            if (!livesInLeganes) {
                string leganesEntryRaw <- rnd_choice(leganesEntryProbabilities);
                string leganesEntry <- leganesEntryRaw;
                string _entry_norm <- lower_case(leganesEntryRaw);
                if (_entry_norm contains "legan") { leganesEntry <- "Leganes"; }
                else if (_entry_norm contains "alcor") { leganesEntry <- "Alcorcon"; }
                else if (_entry_norm contains "fuenla") { leganesEntry <- "Fuenlabrada"; }
                else if (_entry_norm contains "getafe") { leganesEntry <- "Getafe norte"; }
                else if (_entry_norm contains "humanes") { leganesEntry <- "Extremadura"; }
                else if (_entry_norm contains "madr") { leganesEntry <- "Madrid"; }
                else if (_entry_norm contains "mostol" or _entry_norm contains "stol" or _entry_norm contains "mÃ³stol") { leganesEntry <- "Mostoles"; }
                if (leganesEntry != nil and !(leganesEntry = "Leganes")) {
                    building externalHouse <- cityEntryBuildings[leganesEntry];
                    if (externalHouse = nil) {
                        externalHouse <- first(building where (each.buildingType = "city" and each.buildingName = leganesEntry));
                    }
                    if (externalHouse != nil) {
                        house <- externalHouse;
                        if (externalHouse.district != nil and externalHouse.district != "") { district <- externalHouse.district; }
                    }
                }
            }
        }

        string selectedHouseholdType <- "";
        if (hh_size_i = 1 and type_cursor_1 < length(type_plan_1)) {
            selectedHouseholdType <- type_plan_1[type_cursor_1];
            type_cursor_1 <- type_cursor_1 + 1;
        } else if (hh_size_i = 2 and type_cursor_2 < length(type_plan_2)) {
            selectedHouseholdType <- type_plan_2[type_cursor_2];
            type_cursor_2 <- type_cursor_2 + 1;
        } else if (hh_size_i = 3 and type_cursor_3 < length(type_plan_3)) {
            selectedHouseholdType <- type_plan_3[type_cursor_3];
            type_cursor_3 <- type_cursor_3 + 1;
        } else if (hh_size_i = 4 and type_cursor_4 < length(type_plan_4)) {
            selectedHouseholdType <- type_plan_4[type_cursor_4];
            type_cursor_4 <- type_cursor_4 + 1;
        } else if (hh_size_i >= 5 and type_cursor_5p < length(type_plan_5p)) {
            selectedHouseholdType <- type_plan_5p[type_cursor_5p];
            type_cursor_5p <- type_cursor_5p + 1;
        } else {
            selectedHouseholdType <- sample_household_type_by_size(hh_size_i);
        }
        if (selectedHouseholdType = nil or selectedHouseholdType = "") {
            selectedHouseholdType <- "Otro tipo de hogar";
        }
        string ht <- lower_case(selectedHouseholdType);
        bool has_minor_25 <- (ht contains "menor" and ht contains "25");
        bool all_children_25p <- (ht contains "todos" and ht contains "25");
        bool is_single_parent <- ht contains "progenitor";
        bool is_couple <- ht contains "pareja";
        bool has_children <- ht contains "hijo";
        bool has_other_persons <- ht contains "otra";

        list<Person> householdMembers <- [];

        if (numMembers = "1 persona") {
            Person person <- nil;
            if (ht contains "muj" and ht contains "65" and ht contains "menor") {
                person <- getPerson("female", 18, 65, nil, selectedHouseholdType, household[0], false);
            } else if (ht contains "hom" and ht contains "65" and ht contains "menor") {
                person <- getPerson("male", 18, 65, nil, selectedHouseholdType, household[0], false);
            } else if (ht contains "muj" and ht contains "65") {
                person <- getPerson("female", 65, 99, nil, selectedHouseholdType, household[0], false);
            } else if (ht contains "hom" and ht contains "65") {
                person <- getPerson("male", 65, 99, nil, selectedHouseholdType, household[0], false);
            } else {
                person <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
            }
            householdMembers <- householdMembers + person;
        } else if (numMembers = "2 personas") {
            if (is_single_parent and has_minor_25) {
                Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child + parent;
            } else if (is_single_parent and all_children_25p) {
                Person child <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child + parent;
            } else if (is_couple and !has_children) {
                Person person <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person partner <- matchPartner(person, household[0]);
                householdMembers <- householdMembers + person + partner;
            } else {
                Person person1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person person2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + person1 + person2;
            }
        } else if (numMembers = "3 personas") {
            if (is_single_parent and has_minor_25) {
                Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child1 + child2 + parent;
            } else if (is_single_parent and all_children_25p) {
                Person child1 <- getPerson(nil, 25, 99, [], selectedHouseholdType, household[0], true);
                Person child2 <- getPerson(nil, child1.age, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child1 + child2 + parent;
            } else if (is_couple and has_children and has_minor_25) {
                Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person partner1 <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                householdMembers <- householdMembers + child + partner1 + partner2;
            } else if (is_couple and has_children and all_children_25p) {
                Person child <- getPerson(nil, 25, 99, [], selectedHouseholdType, household[0], true);
                Person partner1 <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                householdMembers <- householdMembers + child + partner1 + partner2;
            } else if (has_other_persons and has_minor_25) {
                Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person otherPerson <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child + parent + otherPerson;
            } else {
                Person p1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p3 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + p1 + p2 + p3;
            }
        } else if (numMembers = "4 personas") {
            if (is_single_parent and has_minor_25) {
                Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person child3 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child1 + child2 + child3 + parent;
            } else if (is_single_parent and all_children_25p) {
                Person child1 <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
                Person child2 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person child3 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child1 + child2 + child3 + parent;
            } else if (is_couple and has_children and has_minor_25) {
                Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person child2 <- getPerson(nil, 25, 35, nil, selectedHouseholdType, household[0], false);
                Person partner1 <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                householdMembers <- householdMembers + child1 + child2 + partner1 + partner2;
            } else if (is_couple and has_children and all_children_25p) {
                Person child1 <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
                Person child2 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], true);
                Person partner1 <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                householdMembers <- householdMembers + child1 + child2 + partner1 + partner2;
            } else if (has_other_persons and has_minor_25) {
                Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner <- matchPartner(parent, household[0]);
                Person otherPerson <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child + parent + partner + otherPerson;
            } else {
                Person p1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p3 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p4 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + p1 + p2 + p3 + p4;
            }
        } else {
            if (is_single_parent and has_minor_25) {
                Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person child3 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person child4 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child1, child2, child3, child4], selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child1 + child2 + child3 + child4 + parent;
            } else if (is_couple and has_children and has_minor_25) {
                Person child1 <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person child2 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person child3 <- getPerson(nil, 0, child1.age + 10, nil, selectedHouseholdType, household[0], false);
                Person partner1 <- getPerson(nil, 18, child1.age + 25, [child1, child2, child3], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                householdMembers <- householdMembers + child1 + child2 + child3 + partner1 + partner2;
            } else if (is_couple and has_children and all_children_25p) {
                Person child1 <- getPerson(nil, 25, 99, nil, selectedHouseholdType, household[0], true);
                Person child2 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], true);
                Person child3 <- getPerson(nil, 25, child1.age + 10, nil, selectedHouseholdType, household[0], true);
                Person partner1 <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                householdMembers <- householdMembers + child1 + child2 + child3 + partner1 + partner2;
            } else if (has_other_persons and has_minor_25) {
                Person child <- getPerson(nil, 0, 25, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner <- matchPartner(parent, household[0]);
                Person otherPerson1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person otherPerson2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + child + parent + partner + otherPerson1 + otherPerson2;
            } else {
                Person p1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p3 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p4 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person p5 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + p1 + p2 + p3 + p4 + p5;
            }
        }

        loop while: length(householdMembers) < hh_size_i {
            Person filler <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
            householdMembers <- householdMembers + filler;
        }
        loop while: length(householdMembers) > hh_size_i {
            Person overflow <- last(householdMembers);
            householdMembers <- householdMembers - overflow;
            ask overflow { do die; }
        }

        household[0].numberPersons <- numMembers;
        household[0].members <- list<Person>(householdMembers);
        household[0].nucleusMemberRefs <- [];
        household[0].householdType <- selectedHouseholdType;
        household[0].householdTypeTheoretical <- selectedHouseholdType;
        household[0].householdTypeGenerated <- selectedHouseholdType;
        households <- households + household;
        generated_households <- generated_households + 1;

        int current_people <- length(Person);
        if (current_people >= next_progress or current_people = numPeople) {
            float pct <- with_precision((current_people * 100.0) / max(numPeople, 1), 2);
            write("Population generation progress: " + current_people + "/" + numPeople
                + " (" + pct + "%), households: " + length(households));
            next_progress <- next_progress + progress_interval;
        }
    }

    if (!empty(households)) {
        if (verbose_population_logs) {
            write("Household postprocessing mode: sequential (global scope)");
        }
        loop h over: households {
            string hh_type <- (h.householdTypeGenerated = nil or h.householdTypeGenerated = "") ? h.householdType : h.householdTypeGenerated;
            list<Person> fixed_members <- enforce_household_relationships(hh_type, h.members);
            list<Person> householdCoreMembers <- infer_household_core_members(hh_type, fixed_members);
            list<string> householdCoreRefs <- [];
            loop cp over: householdCoreMembers {
                if (cp != nil and cp.name != nil and !(cp.name in householdCoreRefs)) {
                    householdCoreRefs <- householdCoreRefs + cp.name;
                }
            }
            h.members <- fixed_members;
            h.nucleusMemberRefs <- householdCoreRefs;
        }
    }

    write("Households created with structure constraints: " + generated_households
        + " | persons generated: " + length(Person)
        + " | blueprint remainder: " + populationBlueprintAvailable);
    return length(households);
}
// getPerson function: creates a person with his or her characteristics
	///////////////////////////////////////////////////////////////
	int sample_hour_from_probabilities(map<string, float> probs) {
	    return (rnd_choice(probs) as_int 10);
	}

	int sample_end_hour_for_start(int start_work_hour) {
	    int end_hour <- sample_hour_from_probabilities(workEndHourProbabilities);
	    int guard <- 0;
	    loop while: end_hour <= start_work_hour and guard < 12 {
	        end_hour <- sample_hour_from_probabilities(workEndHourProbabilities);
	        guard <- guard + 1;
	    }
	    if (end_hour <= start_work_hour) {
	        int shiftDuration <- sample_hour_from_probabilities(workDurationHourProbabilities);
	        end_hour <- start_work_hour + shiftDuration;
	    }
	    if (end_hour < minWorkEnd) { end_hour <- minWorkEnd; }
	    if (end_hour > maxWorkEnd) { end_hour <- maxWorkEnd; }
	    if (end_hour <= start_work_hour) { end_hour <- min(maxWorkEnd, start_work_hour + 1); }
	    return end_hour;
	}

	Person getPerson(string sex, int minAge, int maxAge, list<Person> children, string householdType, Household household, bool decreasingBias) {
	    // Adjust age limits based on the ages of provided children
	    string motherMaxAgeRange;
	    int oldestChildAge;
	    if (children != nil) {
	        // Find the oldest childÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢s age
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
	    string requested_gender <- (sex = nil) ? nil : normalize_gender_label(sex);
	    map<string, string> blueprint <- pull_population_blueprint(requested_gender, minAge, maxAge);

	    int ageValue <- rnd(minAge, maxAge, 1);
	    string raw_gender <- (requested_gender = nil) ? (rnd_choice(sexProbabilities) as string) : requested_gender;
	    string gender <- normalize_gender_label(raw_gender);
	    string ageRange <- age_ranges first_with ((split_with(each, "-")[1] as_int 10) >= ageValue);
	    if (ageRange = nil) { ageRange <- "100-120"; }

	    if (blueprint != nil) {
	        string bp_gender <- (blueprint["gender"] = nil) ? gender : normalize_gender_label(blueprint["gender"] as string);
	        string bp_age_range <- (blueprint["age_range"] = nil) ? "" : (blueprint["age_range"] as string);
	        if (bp_age_range = nil or bp_age_range = "") { bp_age_range <- ageRange; }
	        if (bp_age_range = nil or bp_age_range = "" or !(bp_age_range in age_ranges)) {
	            bp_age_range <- age_ranges first_with ((split_with(each, "-")[1] as_int 10) >= ageValue);
	            if (bp_age_range = nil) { bp_age_range <- "100-120"; }
	        }

	        if (bp_age_range != nil and bp_age_range contains "-") {
	            list<string> bp_parts <- split_with(bp_age_range, "-");
	            if (length(bp_parts) >= 2) {
	                int bp_min <- bp_parts[0] as_int 10;
	                int bp_max <- bp_parts[1] as_int 10;
	                int sample_min <- max(minAge, bp_min);
	                int sample_max <- min(maxAge, bp_max);
	                if (sample_max < sample_min) {
	                    sample_min <- bp_min;
	                    sample_max <- bp_max;
	                }
	                ageValue <- rnd(sample_min, sample_max, 1);
	            }
	        }
	        gender <- bp_gender;
	        ageRange <- bp_age_range;
	    }

	    if (ageRange = nil) { ageRange <- "100-120"; }
	    if (!(ageRange in age_ranges)) {
	        ageRange <- age_ranges first_with ((split_with(each, "-")[1] as_int 10) >= ageValue);
	        if (ageRange = nil) { ageRange <- "100-120"; }
	    }

	    int selectedIndex <- age_ranges index_of ageRange;
	    if (selectedIndex >= 0) { age_counts[selectedIndex] <- age_counts[selectedIndex] + 1; }
	
	    // Generate work schedule and sleep time with non-uniform tails
	    int startWork <- sample_hour_from_probabilities(workStartHourProbabilities);
	    if (startWork < minWorkStart) { startWork <- minWorkStart; }
	    if (startWork > maxWorkStart) { startWork <- maxWorkStart; }
	    int endWork <- sample_end_hour_for_start(startWork);
	    int hoursSleep <- rnd(7, 9);
	    int calculatedBedtime <- (startWork - hoursSleep) > 0
	        ? (startWork - hoursSleep)
	        : (24 + (startWork - hoursSleep));
	    if (verbose_population_logs) {
	        write("start_work: " + startWork + " hours_sleep: " + hoursSleep + " bedtime: " + calculatedBedtime);
	    }
	
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
	            // Canonical gender labels: male/female
	            if (p.gender = "male") {
	                child.father <- p;
	            } else {
	                child.mother <- p;
	            }
	        }
	        p.children <- children;
	    }
	
	    // Log a summary of the created Person
	    if (verbose_population_logs) {
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
	    }
	    return p;
	}
}
    
/**
 * 
     ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€
    ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ     ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€
    ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
    ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ  ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ËœÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬â€ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ   ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬â€œÃ‹â€ ÃƒÂ¢Ã¢â‚¬Â¢Ã¢â‚¬Ëœ
    ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â  ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â  ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â  ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â   ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â   ÃƒÂ¢Ã¢â‚¬Â¢Ã…Â¡ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
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
        string municipalityCode <- (municipality = nil or municipality = "") ? "28074" : split_with(municipality, " ")[0];
        string householdSizeLower <- lower_case(householdSize as string);
        string normalizedSize <- nil;
        if (householdSizeLower contains "1") { normalizedSize <- "1 persona"; }
        else if (householdSizeLower contains "2") { normalizedSize <- "2 personas"; }
        else if (householdSizeLower contains "3") { normalizedSize <- "3 personas"; }
        else if (householdSizeLower contains "4") { normalizedSize <- "4 personas"; }
        else if (householdSizeLower contains "5") { normalizedSize <- "5 o mas personas"; }
        if (normalizedSize = nil) { return map<string, float>(map([])); }
        list<list> results <- list<list>(select(
            params: PARAMS,
            select: "WITH Desglose AS (SELECT TamanoHogar, EstructuraHogar, SUM(Total) AS Hogares FROM Hogares WHERE Municipio LIKE ? AND TamanoHogar NOT LIKE 'Total%' AND EstructuraHogar NOT LIKE 'Total%' GROUP BY TamanoHogar, EstructuraHogar), ConPorcentajes AS (SELECT TamanoHogar, EstructuraHogar, Hogares, (Hogares * 1.0) / NULLIF(SUM(Hogares) OVER (PARTITION BY TamanoHogar), 0) AS PorcentajeDentroTamano FROM Desglose WHERE Hogares > 0) SELECT TamanoHogar, EstructuraHogar, PorcentajeDentroTamano FROM ConPorcentajes",
            values: [municipalityCode + " %"]
        ));
        map<string, float> totalsByStructure <- map<string, float>(map([]));
        float totalForSize <- 0.0;
        loop ls over: list<list>(results[2]) {
            string rawSize <- lower_case(ls[0] as string);
            string sizeLabel <- nil;
            if (rawSize contains "1") { sizeLabel <- "1 persona"; }
            else if (rawSize contains "2") { sizeLabel <- "2 personas"; }
            else if (rawSize contains "3") { sizeLabel <- "3 personas"; }
            else if (rawSize contains "4") { sizeLabel <- "4 personas"; }
            else if (rawSize contains "5") { sizeLabel <- "5 o mas personas"; }
            if (sizeLabel = normalizedSize) {
                string structure <- ls[1] as string;
                string structureLower <- lower_case(structure);
                if (!(structureLower contains "total")) {
                    float probability <- max(0.0, ls[2] as float);
                    float current <- (totalsByStructure[structure] = nil) ? 0.0 : totalsByStructure[structure];
                    totalsByStructure[structure] <- current + probability;
                    totalForSize <- totalForSize + probability;
                }
            }
        }
        map<string, float> probabilityVector <- map<string, float>(map([]));
        if (totalForSize <= 0.0) { return probabilityVector; }
        loop key over: keys(totalsByStructure) {
            probabilityVector[key] <- totalsByStructure[key] / totalForSize;
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
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            add value at: key to: probabilityVector;
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
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            add value at: key to: probabilityVector;
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
        loop ls over: list<list>(results[2]) {
            // Assumes the query returns two columns: category and its probability
            string category <- ls[0] as string;
            float value <- ls[1] as float;
            add value at: category to: probabilityVector;
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
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            add value at: key to: probabilityVector;
        }
        return probabilityVector; 
    }

    // Read entry or exit probabilities for LeganÃƒÆ’Ã‚Â©s based on type ("entrada" or "salida")
    action readLeganesEntryExitProbabilities(string type) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT Municipio, CASE WHEN ? = 'entrada' THEN Probabilidad_Entradas WHEN ? = 'salida' THEN Probabilidad_Salidas ELSE NULL END AS Probabilidad FROM entradasYSalidasLeganes;", 
            values: [type, type]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            add value at: key to: probabilityVector;
        }
        return probabilityVector;
    }

    // Read district distribution probabilities for LeganÃƒÆ’Ã‚Â©s
    action readDistrictProbabilities {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT Distrito, Total_porcentaje FROM DistribucionDistritosLeganes WHERE Distrito <> 'TOTALES' ORDER BY Distrito;", 
            values: []
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- ls[1] as float;
            add value at: key to: probabilityVector;
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
        loop ls over: list<list>(results[2]) {
            string key <- ls[1] as string; // use wife's age as the key
            float value <- ls[3] as float;
            add value at: key to: probabilityVector;
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
        loop ls over: list<list>(results[2]) {
            string key <- ls[1] as string; // use husband's age as the key
            float value <- ls[3] as float;
            add value at: key to: probabilityVector;
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
        loop ls over: list<list>(results[2]) {
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
        string municipalityCode <- (municipality = nil or municipality = "") ? "28074" : split_with(municipality, " ")[0];
        list<list> results <- list<list>(select(
            params: PARAMS,
            select: "WITH Totales AS (SELECT TamanoHogar, SUM(Total) AS TotalHogares FROM Hogares WHERE Municipio LIKE ? AND EstructuraHogar = 'Total (estructura del hogar)' AND (TamanoHogar IN ('1 persona','2 personas','3 personas','4 personas','5 o mas personas') OR TamanoHogar LIKE '5 o% personas') GROUP BY TamanoHogar) SELECT TamanoHogar, TotalHogares, ROUND(100.0 * TotalHogares / SUM(TotalHogares) OVER (), 6) AS Porcentaje FROM Totales ORDER BY CASE TamanoHogar WHEN '1 persona' THEN 1 WHEN '2 personas' THEN 2 WHEN '3 personas' THEN 3 WHEN '4 personas' THEN 4 ELSE 5 END",
            values: [municipalityCode + " %"]
        ));
        map<string, float> percentageVector <- map<string, float>(map([
            "1 persona" :: 0.0,
            "2 personas" :: 0.0,
            "3 personas" :: 0.0,
            "4 personas" :: 0.0,
            "5 o mas personas" :: 0.0
        ]));
        float totalHouseholds <- 0.0;
        loop row over: list<list>(results[2]) {
            string rawSize <- lower_case(row[0] as string);
            string normalizedSize <- nil;
            if (rawSize contains "1") { normalizedSize <- "1 persona"; }
            else if (rawSize contains "2") { normalizedSize <- "2 personas"; }
            else if (rawSize contains "3") { normalizedSize <- "3 personas"; }
            else if (rawSize contains "4") { normalizedSize <- "4 personas"; }
            else if (rawSize contains "5") { normalizedSize <- "5 o mas personas"; }
            if (normalizedSize != nil) {
                float count <- max(0.0, row[1] as float);
                percentageVector[normalizedSize] <- percentageVector[normalizedSize] + count;
                totalHouseholds <- totalHouseholds + count;
            }
        }
        if (totalHouseholds <= 0.0) {
            return map<string, float>(map([
                "1 persona" :: 0.2,
                "2 personas" :: 0.2,
                "3 personas" :: 0.2,
                "4 personas" :: 0.2,
                "5 o mas personas" :: 0.2
            ]));
        }
        loop size over: keys(percentageVector) {
            percentageVector[size] <- percentageVector[size] / totalHouseholds;
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
        householdStructureProbabilities5Persons <- readHouseholdStructureProbabilities(statisticsCity, "5 o mas personas");
        motherAgeProbabilities                <- readMotherMaxAgeProbabilities(statisticsAutonomousCommunity);
        map<string, float> rawSexProbabilities <- readSexProbabilities(statisticsProvince);
        sexProbabilities <- map<string, float>(map(["male" :: 0.0, "female" :: 0.0]));
        loop k over: keys(rawSexProbabilities) {
            string g <- lower_case(k as string);
            float v <- rawSexProbabilities[k] as float;
            if (g = "female" or g contains "fem" or g contains "muj") {
                sexProbabilities["female"] <- sexProbabilities["female"] + v;
            } else if (g = "male" or g contains "hom" or g contains "varon" or (g contains "male" and !(g contains "female"))) {
                sexProbabilities["male"] <- sexProbabilities["male"] + v;
            } else {
                sexProbabilities["female"] <- sexProbabilities["female"] + v;
            }
        }
        float sex_sum <- sexProbabilities["male"] + sexProbabilities["female"];
        if (sex_sum <= 0.0) {
            sexProbabilities <- map<string, float>(map(["male" :: 0.5, "female" :: 0.5]));
        } else {
            sexProbabilities["male"] <- sexProbabilities["male"] / sex_sum;
            sexProbabilities["female"] <- sexProbabilities["female"] / sex_sum;
        }
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
    int pedestrianCount <- 0;  // Counter for pedestrians at crossing (replaces boolean)
    bool vehicleCrossing <- false;
    float pedestrianCrossingTimer <- 0.0;  // Timer to detect ghost blocking
    float pedestrianCrossingTimeout <- 30.0;  // Auto-release after 30 seconds

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

    // Reflex to handle ghost blocking of pedestrian crossings
    reflex crossingTimeout {
        if (pedestrianCount > 0) {
            pedestrianCrossingTimer <- pedestrianCrossingTimer + step;
            if (pedestrianCrossingTimer > pedestrianCrossingTimeout) {
                pedestrianCount <- 0;  // Timeout safety: reset counter
                pedestrianCrossingTimer <- 0.0;
                // write "WARNING: Ghost blocking detected at " + self + ". Forced release.";
                ask simLogger { do log_event("CROSSWALK_BLOCK_FORCE_RELEASE," + time + ",system," + myself.name + ",ghost_blocking,0,0"); }
            }
        } else {
            pedestrianCrossingTimer <- 0.0;
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
    string householdType;               // Type of household (legacy field)
    string householdTypeTheoretical;    // Structure sampled from DB probabilities
    string householdTypeGenerated;      // Structure actually instantiated in simulation
    list<Person> members;               // List of persons in this household
    list<string> nucleusMemberRefs;     // References (names) of core household members
    string numberPersons;               // Number of members as string
    string district;                    // District where the house is located
    building house;                     // Reference to the building object
    init {
        members <- [];                  // Initialize the members list
        nucleusMemberRefs <- [];
        householdTypeTheoretical <- "";
        householdTypeGenerated <- "";
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
                    ps.waitingForTrain <- false;
                    ps.startJourney <- true;
                    if (simLogger != nil) {
                        string alight_person <- ps.name;
                        string alight_station <- current_target.name;
                        ask simLogger {
                            do log_event("TRAIN_ALIGHT_CONTINUE," + time + "," + alight_person + "," + alight_station + ",resume_to_final_target,0,0");
                        }
                    }
                }
                passengers <- passengers - passengersGettingOff;
            }
            else {
                // Final destination reached: move all remaining passengers to target point
                loop ps over: passengers {
                    if (ps.the_final_target != nil) {
                        ps.location <- point(ps.the_final_target);
                    }
                    ps.waitingForTrain <- false;
                    ps.startJourney <- false;
                    ps.isMoving <- false;
                    ps.stopped <- true;
                    ask ps { do end_trip_log("COMPLETED"); }
                    ps.the_target <- nil;
                    ps.the_final_target <- nil;
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
    // When a train breaks down, it stops and prepares for recovery after 3 minutes.
    reflex breakdown when: !breakdown and flip(probabilityBreakdown) {
        breakdown <- true;
        max_speed <- 0.0;
        write "Train " + self + " has broken down. It will be removed in 3 minutes.";
    }
    
    // Recovery logic for trains
    reflex handleBreakdown when: breakdown {
        contStop <- contStop + step;
        if (contStop >= 3.0 #mn) {
            loop p over: passengers {
                if (p.living_place != nil) {
                    p.location <- p.living_place.location; // Return passengers home
                }
                p.the_target <- nil;
                p.isMoving <- false;
                p.stopped <- true;
                ask p { do end_trip_log("ABORTED_TRAIN_BREAKDOWN"); }
            }
            write "Broken down train " + self + " removed from tracks.";
            do die;
        }
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
    
    // Breakdown and Stuck recovery variables
    float breakdown_timer <- 0.0;
    float breakdown_duration <- broken_removal_minutes; // Removal delay once broken
    float stuck_recovery_duration <- 15.0 #mn; // Legacy; no removal uses this
    
    
    // References to route intersections
    crossroads initialCrossroad;
    crossroads targetCrossroads;
    
    // Congestion tracking variables
    float thresholdStucked <- 1.0 #mn;         // Default threshold for attempting escape
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
            // NOTE: current_lane removed in GAMA 2025-06 - using simplified lane positioning
            float dist <- (roads(current_road).lanes - mean(range(num_lanes_occupied - 1)) - 0.5) * lane_width;
            if (using_linked_road) {
                dist <- -dist;
            }
            point shift_pt <- { cos(heading + 90) * dist, sin(heading + 90) * dist };
            return location + shift_pt;
        } else {
            return {0, 0};
        }
    }

    // Incoming direction vector at a node (from node toward upstream)
    point incoming_vector(roads r) {
        list<point> pts <- r.shape.points;
        if (length(pts) < 2) { return {0.0, 0.0}; }
        point p_last <- last(pts);
        point p_prev <- pts[length(pts) - 2];
        return (p_prev - p_last);
    }

    // Decide whether right-priority should be ignored due to yield-controlled entry on the right
    bool should_ignore_right_priority {
        if (current_target = nil or current_road = nil) { return false; }
        crossroads node <- crossroads(current_target);
        roads curRoad <- roads(current_road);
        point v_cur <- incoming_vector(curRoad);
        if (v_cur = {0.0, 0.0}) { return false; }

        bool found_yield_right_with_vehicle <- false;
        bool found_non_yield_right <- false;

        loop k over: node.roads_in {
            if (roads(k) = curRoad) { continue; }
            roads r <- roads(k);
            point v_in <- incoming_vector(r);
            if (v_in = {0.0, 0.0}) { continue; }
            float cross <- (v_cur.x * v_in.y) - (v_cur.y * v_in.x);
            if (cross < 0.0) {
                bool has_vehicle_near <- !empty(r.all_agents where (!dead(each) and (each.location distance_to node.location < 15.0 #meters)));
                if (has_vehicle_near) {
                    if (crossroads(r.source_node).isYield) {
                        found_yield_right_with_vehicle <- true;
                    } else {
                        found_non_yield_right <- true;
                    }
                }
            }
        }
        return (found_yield_right_with_vehicle and !found_non_yield_right);
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
            float dist <- distance_to_current_target;
            // Dynamic trigger distance: ensures detection even at high speeds (lookahead 2 steps + safety)
            float triggerDist <- max(10.0, speed * step * 2.5);

            // 1. Cleanup Stale Flags (Transition Handling)
            if (!nextCrossroad.isYield) { nextIsYield <- false; carInAYield <- false; }
            if (!nextCrossroad.isStop) { nextIsStop <- false; carStopInAStop <- false; }
            if (!nextCrossroad.isZebraCrossing) { nextIsZebra <- false; carStopInAZebraCrossing <- false; }

            // 2. Yield Logic
            if (nextCrossroad.isYield) {
                if (!nextIsYield and dist <= triggerDist) {
                    nextIsYield <- true;
                    carInAYield <- true;
                }
            }

            // 3. Stop Logic
            if (nextCrossroad.isStop) {
                if (!nextIsStop and dist <= triggerDist) {
                    nextIsStop <- true;
                    carStopInAStop <- true;
                    contStop <- 0.0;
                }
            }

            // 4. Zebra Logic
            if (nextCrossroad.isZebraCrossing) {
                if (nextCrossroad.pedestrianCount > 0) {
                    if (!nextIsZebra and dist <= triggerDist) {
                        nextIsZebra <- true;
                        carStopInAZebraCrossing <- true;
                        nextCrossroad.stop <- list<list>(roads(current_road));
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
            if (nextCrossroad.pedestrianCount > 0) {
                isBlocked <- true;
            }
        }
        if (isBlocked) {
            nextCrossroad.stop <- list<list>(current_road);
        } else {
            nextCrossroad.stop <- [];
            carStopInAZebraCrossing <- false;
            contStop <- 0.0;
            counterStucked <- 0.0; // Reset stuck timer when starting to move through zebra
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
            if (roads(k) != current_road) {
                // Check if any LIVE agent on the other road is within safety distance (15m)
                if (!empty(roads(k).all_agents where (!dead(each) and (each.location distance_to nextCrossroad.location < 15.0 #meters)))) {
                    isBlocked <- true;
                }
            }
        }
        if (isBlocked) {
            nextCrossroad.stop <- list<list>(roads(current_road));
            carStopInAYield <- true;
        } else {
            nextCrossroad.stop <- [];
            carStopInAYield <- false;
            counterStucked <- 0.0; // Reset stuck timer when starting to move through yield
            // Removed clearing of carInAYield/nextIsYield to allow continuous checking until passed
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
                if (roads(k) != current_road) {
                    // Check if any LIVE agent on the other road is within safety distance (15m)
                     if (!empty(roads(k).all_agents where (!dead(each) and (each.location distance_to nextCrossroadStop.location < 15.0 #meters)))) {
                        isBlocked <- true;
                    }
                }
            }
        }
        if (isBlocked) {
            nextCrossroadStop.stop <- list<list>(roads(current_road));
        } else {
            nextCrossroadStop.stop <- [];
            carStopInAStop <- false;
            contStop <- 0.0;
            counterStucked <- 0.0; // Reset stuck timer when starting to move through stop
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Simulate vehicle breakdown
    // When a car breaks down, its speed is set to 0.0 to stop movement.
    /////////////////////////////////////////////////////////////
    reflex breakdown when: !breakdown and flip(probabilityBreakdown) {
        breakdown <- true;
        breakdown_timer <- 0.0;
        max_speed <- 0.0;
        write "Vehicle " + self + " has broken down. It will be removed in " + (breakdown_duration / 60) + " minutes.";
    }

    ////////////////_RECOVERY_LOGIC_/////////////////////////////
    // Reflex: Handle removal for both Breakdown and Stuck states
    // Breakdown: Removes car after breakdown_duration only if broken.
    // Stuck logic does not trigger removal.
    /////////////////////////////////////////////////////////////
    reflex handleRemoval when: breakdown {
        breakdown_timer <- breakdown_timer + step;
        if (breakdown_timer >= breakdown_duration) {
            string reason <- "vehicle breakdown";
            loop p over: passengers {
                if (p.living_place != nil) {
                    p.location <- p.living_place.location; // Teleport back home
                }
                p.the_target <- nil;
                p.isMoving <- false;
                p.stopped <- true;
                ask p { do end_trip_log("ABORTED_" + (myself.breakdown ? "BREAKDOWN" : "STUCK")); }
                write "Recovery: Passenger " + p + " returned to origin due to " + reason + ".";
            }
            write "Recovery Complete: Vehicle " + self + " removed due to " + reason + ".";
            do die;
        }
    }

    // Reset timer if breakdown is cleared (future repair logic safety)
    reflex resetBreakdownTimer when: !breakdown and breakdown_timer > 0.0 {
        breakdown_timer <- 0.0;
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
    reflex moveNormalCars when: current_path != nil and final_target != nil and carStopInAStop = false and carStopInAZebraCrossing = false and carStopInAYield = false and !breakdown {
        // Run traffic control BEFORE driving to detect signals in time
        if (final_target != nil) {
            do trafficControl;
        }

        float saved_proba <- proba_respect_priorities;
        if (should_ignore_right_priority()) {
            proba_respect_priorities <- 0.0;
        }
        do drive;
        proba_respect_priorities <- saved_proba;
        
        if (final_target != nil) {
            // GRIDLOCK DETECTION: Use real_speed (actual movement) instead of speed (target)
            if (real_speed < 0.01 #km / #h) { 
                // Only increment if we are either leading or truly blocked (no car close in front)
                // This prevents deleting vehicles in normal queues.
                if (empty(vehicles at_distance 5.0 #meters)) {
                    counterStucked <- counterStucked + step;
                }
                
                // ESCALATION: Increase lane change probability every 'thresholdStucked' period
                int stepsThreshold <- int(thresholdStucked / step);
                if (stepsThreshold > 0 and (int(counterStucked / step) mod stepsThreshold = 0)) {
                    proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.2]);
                }
            } else {
                // RESET: Any movement (> 0.01 km/h) clears the stuck timer
                counterStucked <- 0.0;
                proba_use_linked_road <- 0.0;
            }
            // Removed: do trafficControl; (Moved to top)
        } else {
            // Disembark passengers at destination
            loop p over: passengers {
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                }
                ask p { do end_trip_log("COMPLETED"); }
                p.the_target <- nil;
                p.stopped <- true;
            }
            do die;
        }
    }

    // Reflex: Update and calculate CO2 consumption
    reflex updateAndCalculateFuelConsumption when: final_target != nil and calculate_CO2 {
        float consumoStep <- step * 60 * speed * (CO2_g_km / 1000) / 1000;  // real_speed replaced with speed
        consumoCO2 <- consumoStep;
    }

    aspect default {
        if (render3D) {
            point loc;
            if (current_road = nil) {
                loc <- location;
            } else {
                // NOTE: current_lane removed in GAMA 2025-06 - using simplified positioning
                float val <- roads(current_road).lanes * 0.5;
                val <- using_linked_road ? -val : val;  // on_linked_road renamed to using_linked_road
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
        currentTrip.tripCost <- currentTrip.tripTime * 0.05;                       // Calculate fare at ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬0.05 per unit time
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

    // Reflex: Electric cars with low battery ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ navigate to charger
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
       and carStopInAZebraCrossing = false 
       and !breakdown {
       
       float saved_proba <- proba_respect_priorities;
       if (should_ignore_right_priority()) {
           proba_respect_priorities <- 0.0;
       }
       do drive;          // Perform driving step
       proba_respect_priorities <- saved_proba;
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
                if (real_speed < 0.01 #km / #h) {
                    // Only increment if we are either leading or truly blocked (no car close in front)
                    if (empty(vehicles at_distance 5.0 #meters)) {
                        counterStucked <- counterStucked + step;
                    }
                    int stepsThreshold <- int(thresholdStucked / step);
                    if (stepsThreshold > 0 and (int(counterStucked / step) mod stepsThreshold = 0)) {
                        proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.2]);
                    }
                } else {
                    // RESET: Any movement (> 0.01 km/h) clears the stuck timer
                    counterStucked <- 0.0;
                    proba_use_linked_road <- 0.0;
                }
               do trafficControl;
           
            // Arrived or no path to advance
            } else {
                if (final_target != nil) {
                    write "Vehicle " + self + " has reached destination: " + final_target;
                } else {
                    write "Vehicle " + self + " ha llegado a su destino";
                }
           
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
                       if (p.the_target != nil) {
                           p.location <- p.the_target.location;
                       }
                       ask p { do end_trip_log("COMPLETED"); }
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
                // NOTE: current_lane removed in GAMA 2025-06 - using simplified positioning
                float val <- roads(current_road).lanes * 0.5;
                val <- using_linked_road ? -val : val;  // on_linked_road renamed to using_linked_road
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
    // Guards to avoid losing schedule triggers due exact-minute checks
    int last_work_departure_day <- -1;
    int last_home_return_day <- -1;

    // Variables specific to walker functionality
    bool isMoving <- false;
    crossroads start;
    crossroads finishPoint;               // Renamed from finishPn
    path current_path;
    bool startJourney <- false;           // Renamed from iniciarSalida
    bool waitingForTrain <- false;

    // --- Traceability ---
    string current_trip_id <- nil;
    string current_origin_type <- "home";
    point current_origin_geom <- location;
    float current_trip_start_time <- 0.0;
    string current_trip_mode <- nil;
    string current_purpose <- nil;
    int trip_counter <- 0;

    action start_trip_log(string mode, string purpose) {
        trip_counter <- trip_counter + 1;
        current_trip_id <- name + "_" + trip_counter;
        current_trip_mode <- mode;
        current_purpose <- purpose;
        // Infer origin type from previous activity or current location
        // For simplicity, we assume if we just finished an activity, we are at that location type
        // But here we rely on what the simulation logic tracked.
        // We'll update origin geom now.
        current_origin_geom <- location;
        current_trip_start_time <- time;
        // origin_type should ideally be updated when arrival happens, for the NEXT trip. 
        // For now let's just use what we have in current_origin_type
        if (simLogger != nil) {
            string target_name <- (the_target != nil and the_target.buildingName != nil) ? the_target.buildingName : "nil";
            string start_details <- "mode:" + mode + "|purpose:" + purpose + "|origin_type:" + current_origin_type + "|target:" + target_name;
            ask simLogger {
                do log_event("TRIP_LOG_START," + time + "," + myself.name + "," + myself.current_trip_id + "," + start_details + ",0,0");
            }
        }
    }

    action end_trip_log(string status) {
        if (current_trip_id != nil and simLogger != nil) {
            building destination <- (the_target != nil) ? the_target : the_final_target;
            string dest_type <- "unknown";
            if (destination != nil) { dest_type <- destination.buildingType; }
            
            float duration <- time - current_trip_start_time;
            string log_line <- name + "," + current_trip_id + "," + current_purpose + "," + current_trip_mode + "," + 
                               current_origin_type + "," + current_origin_geom.x + "," + current_origin_geom.y + "," + 
                               dest_type + "," + location.x + "," + location.y + "," + 
                               current_trip_start_time + "," + time + "," + duration + "," + status + ",0,0,0";
            string end_details <- "status:" + status + "|mode:" + current_trip_mode + "|purpose:" + current_purpose + "|duration:" + duration;
            
            ask simLogger {
                do log_trip(log_line);
                do log_event("TRIP_LOG_END," + time + "," + myself.name + "," + myself.current_trip_id + "," + end_details + ",0,0");
            }
            
            // Prepare for next trip
            if (destination != nil) { current_origin_type <- destination.buildingType; }
            current_trip_id <- nil;
        }
    }
    // --------------------
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
        // Determine if the person works in LeganÃƒÆ’Ã‚Â©s (based on probabilities: 0.41 and 0.59)
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
       
        // If home is not 'city' type and person is young or adult, update workplace based on LeganÃƒÆ’Ã‚Â©s exit probabilities
        if (!(living_place.buildingType = "city") and ((age_group = "Young" and !is_student) or age_group = "Adult")) {
            // Use LeganÃƒÆ’Ã‚Â©s exit probabilities (renamed globally to leganesExitProbabilities)
            string leganesExitRaw <- rnd_choice(leganesExitProbabilities);
            string leganesExit <- leganesExitRaw;
            string _exit_norm <- lower_case(leganesExitRaw);
            if (_exit_norm contains "legan") { leganesExit <- "Leganes"; }
            else if (_exit_norm contains "alcor") { leganesExit <- "Alcorcon"; }
            else if (_exit_norm contains "fuenla") { leganesExit <- "Fuenlabrada"; }
            else if (_exit_norm contains "getafe") { leganesExit <- "Getafe norte"; }
            else if (_exit_norm contains "humanes") { leganesExit <- "Extremadura"; }
            else if (_exit_norm contains "madr") { leganesExit <- "Madrid"; }
            else if (_exit_norm contains "mostol" or _exit_norm contains "stol" or _exit_norm contains "mÃ³stol") { leganesExit <- "Mostoles"; }
            if (leganesExit != nil and !(leganesExit = "Leganes")) {
                building externalWork <- first(building where (each.buildingType = "city" and each.buildingName = leganesExit));
                if (externalWork != nil) { working_place <- externalWork; }
            }
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
	        bool homeIsCity <- (living_place != nil and living_place.buildingType = "city");
	        bool workIsCity <- (working_place != nil and working_place.buildingType = "city");
	        longDistance <- homeIsCity or workIsCity;
	    }
	    
	    // If forced to walk and not a long distance
	    if (forcedWalkMode) and !longDistance {
	        formOfTransportation <- "walking";
            if (current_trip_id = nil) { do start_trip_log("walking", objective); }
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
	            if (simLogger != nil) {
	                string mode_details <- "distance_class:long|chosen:" + formOfTransportation
	                    + "|p_walking:0"
	                    + "|p_car:" + carLongDistanceProbability
	                    + "|p_taxi:" + taxiLongDistanceProbability
	                    + "|p_train:" + trainLongDistanceProbability;
	                ask simLogger {
	                    do log_event("MODE_CHOICE," + time + "," + myself.name + "," + myself.objective + "," + mode_details + ",0,0");
	                }
	            }
	            if (formOfTransportation = "train") {
	                list<building> l <- building where (self intersects each and each.buildingType = "city");
	                if (length(l) > 0) { // Outside current simulation area, in another city l[0]
	                    // Board the train
	                    // Map origin cities to their corresponding stations
	                    crossroads station;
	                    // Mapping of cities to their nearest stations
	                    map<string, string> city_to_station <- [
	                        "Mostoles"      :: "Humanes",
	                        "Extremadura"   :: "Humanes",
	                        "Fuenlabrada"   :: "Humanes",
	                        "Alcorcon"      :: "Humanes",
	                        "Madrid"        :: "Madrid",
	                        "Getafe norte"  :: "Madrid",
	                        "Getafe"        :: "Madrid"
	                    ];
	                    string origin_city <- l[0].buildingName;
	                    string _origin_norm <- lower_case(origin_city);
	                    if (_origin_norm contains "legan") { origin_city <- "Leganes"; }
	                    else if (_origin_norm contains "alcor") { origin_city <- "Alcorcon"; }
	                    else if (_origin_norm contains "fuenla") { origin_city <- "Fuenlabrada"; }
	                    else if (_origin_norm contains "getafe") { origin_city <- "Getafe norte"; }
	                    else if (_origin_norm contains "humanes") { origin_city <- "Extremadura"; }
	                    else if (_origin_norm contains "madr") { origin_city <- "Madrid"; }
	                    else if (_origin_norm contains "mostol" or _origin_norm contains "stol" or _origin_norm contains "mÃ³stol") { origin_city <- "Mostoles"; }
	                    string station_name <- city_to_station[origin_city];
	                    if (station_name != nil) {
	                        // Find the first crossroads matching the station name
	                        station <- first(crossroads where (
	                            each.isTrainStation and each.nameTrainStation = station_name
	                        ));
	                    }
                    if (station != nil) {
                        station.waitingPassengers <- station.waitingPassengers + self;
                        waitingForTrain <- true;
                        if (simLogger != nil) {
                            string station_label <- station.name;
                            ask simLogger {
                                do log_event("TRAIN_QUEUE_ENTER," + time + "," + myself.name + "," + station_label + ",direct_city_transfer,0,0");
                            }
                        }
                    }
                        if (current_trip_id = nil) { do start_trip_log("train", objective); }
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
                        if (current_trip_id = nil) { do start_trip_log("train", objective); }
	                }
	                contadorTrenes <- contadorTrenes + 1;
	            }
	            else if (formOfTransportation = "taxi") {
                    if (current_trip_id = nil) { do start_trip_log("taxi", objective); }
	                ask taxiSwitchboard {
	                    do requestTaxi(myself);
	                }
	                contadorTaxis <- contadorTaxis + 1;
	            }
	            else if (formOfTransportation = "car") {
                    if (current_trip_id = nil) { do start_trip_log("car", objective); }
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
	            if (simLogger != nil) {
	                string mode_details <- "distance_class:short|chosen:" + formOfTransportation
	                    + "|p_walking:" + walkShortDistanceProbability
	                    + "|p_car:" + carShortDistanceProbability
	                    + "|p_taxi:" + taxiShortDistanceProbability
	                    + "|p_train:0";
	                ask simLogger {
	                    do log_event("MODE_CHOICE," + time + "," + myself.name + "," + myself.objective + "," + mode_details + ",0,0");
	                }
	            }
	            if (formOfTransportation = "car") {
                    if (current_trip_id = nil) { do start_trip_log("car", objective); }
	                do instantiate_car;
	                newObjective <- false;
	                contadorCoches <- contadorCoches + 1;
	            }
	            else if (formOfTransportation = "taxi") {
                    if (current_trip_id = nil) { do start_trip_log("taxi", objective); }
	                ask taxiSwitchboard {
	                    do requestTaxi(myself);
	                }
	                newObjective <- false;
	                contadorTaxis <- contadorTaxis + 1;
	            }
	            else if (formOfTransportation = "walking") {
                    if (current_trip_id = nil) { do start_trip_log("walking", objective); }
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
    crossroads activeCrossingNode <- nil;  // Tracks the node we are currently "crossing" to manage car blocking

	reflex walk when: isMoving and finishPoint != nil and (not startJourney) {
	    // Move along the current_path
	    do goto(target: finishPoint, on: streetsNetwork, speed: speed, return_path: true, recompute_path: false);
        
        // Companion Logging (Reduced frequency for performance)
        if (cycle mod 50 = 0) {
            if (mother != nil) { ask simLogger { do log_event("COMPANION_DISTANCE_SAMPLE," + time + "," + myself.name + "," + myself.mother.name + ",mother_dist:" + (myself distance_to myself.mother) + ",0,0"); } }
            if (father != nil) { ask simLogger { do log_event("COMPANION_DISTANCE_SAMPLE," + time + "," + myself.name + "," + myself.father.name + ",father_dist:" + (myself distance_to myself.father) + ",0,0"); } }
            if (partner != nil) { ask simLogger { do log_event("COMPANION_DISTANCE_SAMPLE," + time + "," + myself.name + "," + myself.partner.name + ",partner_dist:" + (myself distance_to myself.partner) + ",0,0"); } }
            if (!empty(children)) { 
                loop c over: children {
                     ask simLogger { do log_event("COMPANION_DISTANCE_SAMPLE," + time + "," + myself.name + "," + c.name + ",child_dist:" + (myself distance_to c) + ",0,0"); }
                }
            }
        }

	    // Get index of current_edge in current_path.edges
	    positionCurrentEdge <- int((current_path = nil) ? nil : current_path.edges index_of current_edge);
	    
	    // 3. Release crossing once passed
	    if (isCrossing) {
	        if (length(self.zebra_edges) > 0 and positionCurrentEdge >= 0) {
	            geometry lastZebraEdge <- last(zebra_edges);
	            int lastZebraEdgeIndex <- current_path.edges index_of lastZebraEdge;
	            if (positionCurrentEdge > lastZebraEdgeIndex) {
	                // Release the active zebra crossing counter
	                if (activeCrossingNode != nil) {
	                    activeCrossingNode.pedestrianCount <- max(0, activeCrossingNode.pedestrianCount - 1);
	                    activeCrossingNode <- nil;
	                }
	                isCrossing <- false;
                    ask simLogger { do log_event("CROSSWALK_EXIT," + time + "," + myself.name + ",unknown_crossing,release_on_move,0,0"); }
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
	        if (crossingNode.isZebraCrossing and !isCrossing) {
	            isCrossing <- true;
	            activeCrossingNode <- crossingNode;
	            crossingNode.pedestrianCount <- crossingNode.pedestrianCount + 1;
                ask simLogger { do log_event("CROSSWALK_ENTER," + time + "," + myself.name + "," + myself.activeCrossingNode.name + ",normal_entry,0,0"); }
	        }
	    }
        
        // 4. Arrival at destination
        if (finishPoint.location = self.location) {
            if (the_target != nil) {
                location <- point(the_target);
            }
            isMoving <- false;
            
            // Releasing crossing if arriving exactly at a zebra
            if (activeCrossingNode != nil) {
                activeCrossingNode.pedestrianCount <- max(0, activeCrossingNode.pedestrianCount - 1);
                ask simLogger { do log_event("CROSSWALK_EXIT," + time + "," + myself.name + "," + myself.activeCrossingNode.name + ",release_on_arrival,0,0"); }
                activeCrossingNode <- nil;
            }
            
            // If using train and arrival at station, enqueue at station
            bool boardingTrainAtStation <- false;
            if (formOfTransportation = "train" 
                and the_target != nil
                and (the_target.railwayType = "station" or the_target.railwayType = "platform")
                and (not waitingForTrain)) {
                stationString <- (the_target.buildingName = "LeganÃƒÆ’Ã‚Â©s") 
                    ? "LeganÃƒÆ’Ã‚Â©s Central" 
                    : the_target.buildingName + ((the_final_target.buildingName = "Madrid") ? " - VÃƒÆ’Ã‚Â­a 1" : " - VÃƒÆ’Ã‚Â­a 2");
                crossroads station <- one_of(crossroads where (
                    each.isTrainStation and each.nameTrainStation = ((the_target.buildingName = "LeganÃƒÆ’Ã‚Â©s") 
                        ? "LeganÃƒÆ’Ã‚Â©s Central" 
                        : the_target.buildingName) + ((the_final_target.buildingName = "Madrid" or the_final_target.buildingName = "Getafe") 
                        ? " - VÃƒÆ’Ã‚Â­a 1" 
                        : " - VÃƒÆ’Ã‚Â­a 2")
                ));
                if (station != nil) {
                    station.waitingPassengers <- station.waitingPassengers + self;
                    waitingForTrain <- true;
                    boardingTrainAtStation <- true;
                    if (simLogger != nil) {
                        string station_label <- station.name;
                        ask simLogger {
                            do log_event("TRAIN_QUEUE_ENTER," + time + "," + myself.name + "," + station_label + ",arrived_station,0,0");
                        }
                    }
                }
                stationAgent <- station;
            }
            finishPoint <- nil;
            stopped <- true;
            if (!boardingTrainAtStation) {
                do end_trip_log("COMPLETED");
            }
            the_target <- nil;
            isCrossing <- false;
            zebra_edges <- [];
        }
    }

    /////////////////////////////////////////////////////////////
    // Reflexes for work, return home, and activities schedules
    /////////////////////////////////////////////////////////////
    reflex time_to_work when: working_place != nil 
                             and objective = "resting" 
                             and stopped
                             and last_work_departure_day != current_date.day
                             and (current_date.hour > start_work or (current_date.hour = start_work and current_date.minute >= delayed_start)) {
        the_target <- working_place;
        objective <- "working";
        newObjective <- true;
        last_work_departure_day <- current_date.day;
        if (simLogger != nil) {
            ask simLogger {
                do log_event("SCHEDULE_WORK_DEPARTURE," + time + "," + myself.name + "," + myself.working_place.buildingType + ",start_work:" + myself.start_work + "|delay_min:" + myself.delayed_start + ",0,0");
            }
        }
    }
    reflex time_to_go_home when: objective = "working" 
                                and stopped
                                and last_home_return_day != current_date.day
                                and (current_date.hour > end_work or (current_date.hour = end_work and current_date.minute >= delayed_start)) {
        the_target <- living_place;
        objective <- "resting";
        newObjective <- true;
        last_home_return_day <- current_date.day;
        if (simLogger != nil) {
            ask simLogger {
                do log_event("SCHEDULE_HOME_RETURN," + time + "," + myself.name + "," + myself.living_place.buildingType + ",end_work:" + myself.end_work + "|delay_min:" + myself.delayed_start + ",0,0");
            }
        }
    }
    reflex come_back_home_after_activity when: inActivity 
                                              and objective != "resting" 
                                              and stopped
                                              and (current_date.hour > hourIsFree or (current_date.hour = hourIsFree and current_date.minute >= delayed_start)) {
        the_target <- living_place;
        objective <- "resting";
        inActivity <- false;
        newObjective <- true;
        if (simLogger != nil) {
            ask simLogger {
                do log_event("SCHEDULE_ACTIVITY_RETURN," + time + "," + myself.name + "," + myself.living_place.buildingType + ",hour_is_free:" + myself.hourIsFree + "|delay_min:" + myself.delayed_start + ",0,0");
            }
        }
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
            list<Person> travelers <- [self] + activity_partners;
            ask travelers { stopped <- false; }
            create normalCars {
                passengers <- travelers;
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
                // MOBIL model parameters (replaces proba_lane_change_down/up in GAMA 2025-06)
                // politeness <- 0.25 + (rnd(250) / 1000);  // FIXME: Variable not found in GAMA 2025-06
                // threshold_lc <- 0.2 + (rnd(300) / 1000); // FIXME: Variable not found in GAMA 2025-06
                proba_respect_priorities <- 1.0 - rnd(200 / 1000);
                proba_respect_stops <- [1.0];
                proba_use_linked_road <- 0.0;
                right_side_driving <- true;
                safety_distance_coeff <- 5 / 9 * 3.6 * (1.5 - rnd(1000) / 1000);  // security renamed to safety
                lane_change_limit <- 2;
                speed_coeff <- 1.0 - (rnd(600) / 1000);
                thresholdStucked <- float((1 + rnd(5)) #mn);
                vehicle_length <- rnd(2.5, 4.0) #m;
                probabilityBreakdown <- 0.000005; // Reduced probability by half (previously 0.00001)
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
        write "Se agregÃƒÆ’Ã‚Â³ la solicitud del pasajero " + p + " a la lista de viajes pendientes.";
        return true;
    }

    // Periodic queue snapshot for SLA diagnostics in analyze_simulation.py
    reflex queueSnapshot when: simLogger != nil and (cycle mod 50 = 0) {
        float avgPendingWait <- (length(pendingTrips) > 0)
            ? mean(pendingTrips collect (current_date - each.requestTime))
            : 0.0;
        ask simLogger {
            do log_event(
                "TAXI_QUEUE_SNAPSHOT," + time + ",switchboard,queue,"
                + length(myself.pendingTrips) + "," + avgPendingWait + "," + myself.freeTaxis
            );
        }
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

species SimulationLogger {
    list<string> trip_logs <- [];
    list<string> event_logs <- [];
    
    // Configurable output file paths
    string trips_file <- "trips.csv";
    string events_file <- "events.csv";
    string population_stats_file <- "population_stats.csv";
    string reference_stats_file <- "reference_stats.csv";
    string households_file <- "households.csv";
    string household_members_file <- "household_members.csv";

    // Setup function to initialize files with headers
    action initialize_logs {
        save "person_id,trip_id,purpose,mode,origin_type,origin_x,origin_y,dest_type,dest_x,dest_y,start_time,end_time,duration,status,path_cost,real_distance,wait_time" 
            to: trips_file rewrite: true;
        save "event_type,time,entity_id,related_id,details,extra_1,extra_2" 
            to: events_file rewrite: true;
        save "metric_group,metric_name,metric_value,metric_unit,source" 
            to: population_stats_file rewrite: true;
        save "metric_group,metric_name,metric_value,metric_unit,source" 
            to: reference_stats_file rewrite: true;
        save "household_id,number_persons,district,household_type_theoretical,household_type_generated,member_count,nucleus_member_refs,house_building_name,house_building_type" 
            to: households_file rewrite: true;
        save "household_id,person_name,gender,age,age_range,father_name,mother_name,partner_name,children_count,living_place_name,working_place_name" 
            to: household_members_file rewrite: true;
    }

    action log_trip(string log_entry) {
        trip_logs <- trip_logs + log_entry;
    }
    
    action log_event(string log_entry) {
        event_logs <- event_logs + log_entry;
    }

    action log_population_metric(string group, string name, float value, string unit, string source) {
        save group + "," + name + "," + value + "," + unit + "," + source
            to: population_stats_file rewrite: false;
    }

    action log_reference_metric(string group, string name, float value, string unit, string source) {
        save group + "," + name + "," + value + "," + unit + "," + source
            to: reference_stats_file rewrite: false;
    }

    action export_household_registry {
        save "household_id,number_persons,district,household_type_theoretical,household_type_generated,member_count,nucleus_member_refs,house_building_name,house_building_type"
            to: households_file rewrite: true;
        save "household_id,person_name,gender,age,age_range,father_name,mother_name,partner_name,children_count,living_place_name,working_place_name"
            to: household_members_file rewrite: true;

        int household_index <- 0;
        loop h over: households {
            household_index <- household_index + 1;
            string household_id <- "HH_" + household_index;
            string household_type_theoretical <- (h.householdTypeTheoretical = nil) ? "" : h.householdTypeTheoretical;
            string household_type_generated <- (h.householdTypeGenerated = nil) ? "" : h.householdTypeGenerated;
            string district_name <- (h.district = nil) ? "" : h.district;
            string nucleus_refs <- "";
            if (h.nucleusMemberRefs != nil and !empty(h.nucleusMemberRefs)) {
                loop i from: 0 to: (length(h.nucleusMemberRefs) - 1) {
                    string sep <- (i = 0) ? "" : "|";
                    nucleus_refs <- nucleus_refs + sep + h.nucleusMemberRefs[i];
                }
            }
            string house_name <- (h.house = nil or h.house.buildingName = nil) ? "" : h.house.buildingName;
            string house_type <- (h.house = nil or h.house.buildingType = nil) ? "" : h.house.buildingType;

            save household_id + "," + h.numberPersons + "," + district_name + "," + household_type_theoretical + "," + household_type_generated + "," + length(h.members) + "," + nucleus_refs + "," + house_name + "," + house_type
                to: households_file rewrite: false;

            loop p over: h.members {
                string father_name <- (p.father = nil) ? "" : p.father.name;
                string mother_name <- (p.mother = nil) ? "" : p.mother.name;
                string partner_name <- (p.partner = nil) ? "" : p.partner.name;
                int children_count <- (p.children = nil) ? 0 : length(p.children);
                string living_place_name <- (p.living_place = nil or p.living_place.buildingName = nil) ? "" : p.living_place.buildingName;
                string working_place_name <- (p.working_place = nil or p.working_place.buildingName = nil) ? "" : p.working_place.buildingName;

                save household_id + "," + p.name + "," + p.gender + "," + p.age + "," + p.age_range + "," + father_name + "," + mother_name + "," + partner_name + "," + children_count + "," + living_place_name + "," + working_place_name
                    to: household_members_file rewrite: false;
            }
        }
    }

    // Snapshot simulated population distributions and input/reference distributions.
    // This is called once after population generation and does not alter model logic.
    action snapshot_population_and_reference {
        int total_people <- length(Person);
        int total_households <- length(households);
        int total_workers <- length(Person where (each.working_place != nil));
        do export_household_registry;

        do log_population_metric("population", "total_people", total_people, "count", "simulation");
        do log_population_metric("population", "total_households", total_households, "count", "simulation");
        do log_population_metric("population", "total_workers", total_workers, "count", "simulation");

        int hh1_count <- length(households where (length(each.members) = 1));
        int hh2_count <- length(households where (length(each.members) = 2));
        int hh3_count <- length(households where (length(each.members) = 3));
        int hh4_count <- length(households where (length(each.members) = 4));
        int hh5p_count <- length(households where (length(each.members) >= 5));
        float hh1 <- (total_households > 0) ? hh1_count / total_households : 0.0;
        float hh2 <- (total_households > 0) ? hh2_count / total_households : 0.0;
        float hh3 <- (total_households > 0) ? hh3_count / total_households : 0.0;
        float hh4 <- (total_households > 0) ? hh4_count / total_households : 0.0;
        float hh5p <- (total_households > 0) ? hh5p_count / total_households : 0.0;
        do log_population_metric("household_size_count", "1 persona", hh1_count, "count", "simulation");
        do log_population_metric("household_size_count", "2 personas", hh2_count, "count", "simulation");
        do log_population_metric("household_size_count", "3 personas", hh3_count, "count", "simulation");
        do log_population_metric("household_size_count", "4 personas", hh4_count, "count", "simulation");
        do log_population_metric("household_size_count", "5 o mas personas", hh5p_count, "count", "simulation");
        do log_population_metric("household_size", "1 persona", hh1, "share", "simulation");
        do log_population_metric("household_size", "2 personas", hh2, "share", "simulation");
        do log_population_metric("household_size", "3 personas", hh3, "share", "simulation");
        do log_population_metric("household_size", "4 personas", hh4, "share", "simulation");
        do log_population_metric("household_size", "5 o mas personas", hh5p, "share", "simulation");

        list<string> household_types <- [];
        loop h over: households {
            if (h.householdType != nil and h.householdType != "" and not (h.householdType in household_types)) {
                household_types <- household_types + h.householdType;
            }
        }
        loop htype over: household_types {
            if (htype != nil and htype != "") {
                int count <- length(households where (each.householdType = htype));
                float share <- (total_households > 0) ? count / total_households : 0.0;
                do log_population_metric("household_type_count", htype, count, "count", "simulation");
                do log_population_metric("household_type", htype, share, "share", "simulation");
            }
        }

        list<string> genders <- [];
        loop p over: Person {
            if (p.gender != nil and p.gender != "" and not (p.gender in genders)) {
                genders <- genders + p.gender;
            }
        }
        loop g over: genders {
            if (g != nil and g != "") {
                int count <- length(Person where (each.gender = g));
                float share <- (total_people > 0) ? count / total_people : 0.0;
                do log_population_metric("gender_count", g, count, "count", "simulation");
                do log_population_metric("gender", g, share, "share", "simulation");
            }
        }

        loop ar over: age_ranges {
            int count <- length(Person where (each.age_range = ar));
            float share <- (total_people > 0) ? count / total_people : 0.0;
            do log_population_metric("age_range_count", ar, count, "count", "simulation");
            do log_population_metric("age_range", ar, share, "share", "simulation");
        }

        loop d over: keys(districtDistributionProbabilities) {
            int count <- length(households where (each.house != nil and each.house.district = d));
            float share <- (total_households > 0) ? count / total_households : 0.0;
            do log_population_metric("district_count", d, count, "count", "simulation");
            do log_population_metric("district", d, share, "share", "simulation");
        }

        // Assigned work schedule distributions in generated population
        loop hour from: 0 to: 23 {
            int start_count <- length(Person where (each.working_place != nil and each.start_work = hour));
            int end_count <- length(Person where (each.working_place != nil and each.end_work = hour));
            if (start_count > 0) {
                do log_population_metric("work_start_hour_count", string(hour), start_count, "count", "simulation");
                do log_population_metric("work_start_hour_share", string(hour), (start_count * 1.0) / max(total_workers, 1), "share", "simulation");
            }
            if (end_count > 0) {
                do log_population_metric("work_end_hour_count", string(hour), end_count, "count", "simulation");
                do log_population_metric("work_end_hour_share", string(hour), (end_count * 1.0) / max(total_workers, 1), "share", "simulation");
            }
        }

        do log_reference_metric("simulation_config", "num_people", numPeople, "count", "input");
        do log_reference_metric("simulation_config", "number_of_electric_taxis", numberOfElectricCars, "count", "input");
        do log_reference_metric("simulation_config", "step_minutes", step, "minutes", "input");
        do log_reference_metric("transport_short_target", "walking", walkShortDistanceProbability, "share", "input");
        do log_reference_metric("transport_short_target", "car", carShortDistanceProbability, "share", "input");
        do log_reference_metric("transport_short_target", "taxi", taxiShortDistanceProbability, "share", "input");
        do log_reference_metric("transport_long_target", "car", carLongDistanceProbability, "share", "input");
        do log_reference_metric("transport_long_target", "train", trainLongDistanceProbability, "share", "input");
        do log_reference_metric("transport_long_target", "taxi", taxiLongDistanceProbability, "share", "input");
        loop k over: keys(workStartHourProbabilities) {
            do log_reference_metric("work_start_target", k, workStartHourProbabilities[k], "share", "input");
        }
        loop k over: keys(workEndHourProbabilities) {
            do log_reference_metric("work_end_target", k, workEndHourProbabilities[k], "share", "input");
        }
        loop k over: keys(workDurationHourProbabilities) {
            do log_reference_metric("work_duration_target", k, workDurationHourProbabilities[k], "share", "input");
        }

        map<string, float> hh_targets <- map<string, float>(map([
            "1 persona" :: 0.0,
            "2 personas" :: 0.0,
            "3 personas" :: 0.0,
            "4 personas" :: 0.0,
            "5 o mas personas" :: 0.0
        ]));
        loop hk over: keys(householdStructureProbabilities) {
            string hkn <- lower_case(hk as string);
            float hv <- householdStructureProbabilities[hk] as float;
            if (!(hkn contains "total")) {
                if (hkn contains "1") { hh_targets["1 persona"] <- hh_targets["1 persona"] + max(0.0, hv); }
                else if (hkn contains "2") { hh_targets["2 personas"] <- hh_targets["2 personas"] + max(0.0, hv); }
                else if (hkn contains "3") { hh_targets["3 personas"] <- hh_targets["3 personas"] + max(0.0, hv); }
                else if (hkn contains "4") { hh_targets["4 personas"] <- hh_targets["4 personas"] + max(0.0, hv); }
                else if (hkn contains "5") { hh_targets["5 o mas personas"] <- hh_targets["5 o mas personas"] + max(0.0, hv); }
            }
        }
        float hh_sum <- 0.0;
        loop hk2 over: keys(hh_targets) { hh_sum <- hh_sum + hh_targets[hk2]; }
        if (hh_sum <= 0.0) {
            hh_targets <- map<string, float>(map([
                "1 persona" :: 0.2,
                "2 personas" :: 0.2,
                "3 personas" :: 0.2,
                "4 personas" :: 0.2,
                "5 o mas personas" :: 0.2
            ]));
        } else {
            loop hk2 over: keys(hh_targets) { hh_targets[hk2] <- hh_targets[hk2] / hh_sum; }
        }
        loop k over: keys(hh_targets) {
            do log_reference_metric("household_size_target", k, hh_targets[k], "share", "db");
        }
        loop k over: keys(sexProbabilities) {
            do log_reference_metric("gender_target", k, sexProbabilities[k], "share", "db");
        }
        loop k over: age_ranges {
            float p <- (ageGroupProbabilities[k] = nil) ? 0.0 : ageGroupProbabilities[k];
            do log_reference_metric("age_range_target", k, p, "share", "db");
        }
        loop k over: keys(districtDistributionProbabilities) {
            do log_reference_metric("district_target", k, districtDistributionProbabilities[k], "share", "db");
        }
        loop k over: keys(orientationProbabilities) {
            do log_reference_metric("orientation_target", k, orientationProbabilities[k], "share", "db");
        }
    }
    
    reflex flush_logs when: (cycle mod 10 = 0) {
        if (!empty(trip_logs)) {
            loop t over: trip_logs {
                save t to: trips_file rewrite: false;
            }
            trip_logs <- [];
        }
        
        if (!empty(event_logs)) {
            loop e over: event_logs {
                save e to: events_file rewrite: false;
            }
            event_logs <- [];
        }
    }
}

// Experiment "Leganes" (full version) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ configures visualization, simulation, vehicles, buses, transport, and defines outputs
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


// Experiment "CO2 Study" ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ focuses on analyzing CO2 consumption
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


// Experiment "AgeDistribution" ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ study of population age distribution
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
