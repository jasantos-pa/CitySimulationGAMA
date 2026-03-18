/**
* Name: Leganes
* Author: Javier Santos Menendez
*/

model Leganes

global {
    // Flag to render the simulation in 3D/2D
	bool render3D <- false;
	bool carsEnhancedAppearance <- true;
	bool showTextChargingPoints <- false;
	
	// Flag to enable vehicle-to-grid (V2G) energy feed from taxis
	bool V2GActivated <- false;
	// Global switch for random breakdowns (disabled by default)
	bool enableBreakdowns <- false;
	
	// Agent counters in the simulation
	int pedestrianTripCounter <- 0;
	int carTripCounter <- 0;
	int taxiTripCounter <- 0;
	int trainTripCounter <- 0;
	
	// Number of people in the simulation
	int numPeople;
	
	// Total number of autonomous vehicles
	int numberOfElectricCars;
	
	// Initial search radius for proximity/fallback lookups (configurable from IDE)
	float initialSearchRadius <- 500.0;
	
	// Flag to show road directions
	bool watchDirections <- false;
	
	// Imported map files
	file shapefileRoads <- file("../includes/Maps/Leganes_clean/ROADS_clean.shp");
	file shapefileCrossroads <- file("../includes/Maps/Leganes_clean/CROSSROADS_clean.shp");
	file shapefileStreets <- file("../includes/Maps/Leganes_clean/STREETS_clean.shp");
	file buildingsShapefile <- file("../includes/Maps/Leganes_clean/BUILDINGS.shp");
	file shapefileRailway <- file("../includes/Maps/Leganes_clean/railway3.shp");
	
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
	map<string, float> coupleAgeGapProbabilities;
	map<string, float> ageGroupProbabilities;
	map<string, float> leganesEntryProbabilities;
	map<string, float> leganesExitProbabilities;
	map<string, float> districtDistributionProbabilities;
	map<string,map<string, float>> husbandAgeCoupleProbabilities;
	map<string,map<string, float>> wifeAgeCoupleProbabilities;
	map<string, int> coupleGapObservedCounts <- map<string, int>(map([
	    "0-4" :: 0,
	    "5-9" :: 0,
	    "10-14" :: 0,
	    "15+" :: 0
	]));
	
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
	
	// Broken-vehicle removal delay
	float broken_removal_minutes <- 3.0 #mn;
	
	// Interactive export configuration
	string agent_export_file <- "agent_export.csv";
	string route_probe_file <- "gama_route_probe_report.csv";
	bool route_probe_header_written <- false;
	int householdSizeFillersAdded <- 0;
	int householdSizeOverflowRemoved <- 0;
	int householdSizeAdjustedHouseholds <- 0;
	int householdSizeFillAdjustedHouseholds <- 0;
	int householdSizeOverflowAdjustedHouseholds <- 0;
	int householdPostprocessRectifiedHouseholds <- 0;
	int householdPostprocessRectifiedPersons <- 0;
	int householdPostprocessHomeRectifiedHouseholds <- 0;
	int householdPostprocessHomeRectifiedPersons <- 0;
	int householdPostprocessPartnerRectifiedHouseholds <- 0;
	int householdPostprocessPartnerRectifiedPersons <- 0;
	int householdPostprocessFatherRectifiedHouseholds <- 0;
	int householdPostprocessFatherRectifiedPersons <- 0;
	int householdPostprocessMotherRectifiedHouseholds <- 0;
	int householdPostprocessMotherRectifiedPersons <- 0;
	int householdPostprocessChildrenRectifiedHouseholds <- 0;
	int householdPostprocessChildrenRectifiedPersons <- 0;
	int populationGetPersonCalls <- 0;
	int blueprintPullAttempts <- 0;
	int blueprintExactMatches <- 0;
	int blueprintAgeOnlyMatches <- 0;
	int blueprintGenderOnlyMatches <- 0;
	int blueprintAnyMatches <- 0;
	int blueprintMisses <- 0;
	int blueprintFallbackPersonGenerations <- 0;
	int blueprintRejectedNonIntersectingAgeCount <- 0;
	int personCreationSoftRelaxStage1Count <- 0;
	int personCreationSoftRelaxStage2Count <- 0;
	int personCreationSoftRelaxStage3Count <- 0;
	int householdHardFallbackCount <- 0;
	int hardConstraintViolationsFinal <- 0;
	map<string, int> householdHardFallbackReasonCounts <- map<string, int>(map([]));
	string hardConstraintFallbackType <- "hard_constraint_fallback";
	int coupleGapTargetBucketHits <- 0;
	int coupleGapAchievedOnTarget <- 0;
	int coupleGapSampleRetries <- 0;
	int coupleGapQuotaSpilloverCount <- 0;
	map<string, int> coupleGapQuotaTargetCounts <- map<string, int>(map([
	    "0-4" :: 0,
	    "5-9" :: 0,
	    "10-14" :: 0,
	    "15+" :: 0
	]));
	map<string, int> coupleGapQuotaUsedCounts <- map<string, int>(map([
	    "0-4" :: 0,
	    "5-9" :: 0,
	    "10-14" :: 0,
	    "15+" :: 0
	]));
	action refresh_taxi_registry {
	    if (taxiCallCenter != nil) {
	        list<electricCars> alive_taxis <- electricCars where (each != nil and !dead(each));
	        taxiCallCenter.registeredTaxis <- alive_taxis;
	        taxiCallCenter.freeTaxis <- length(alive_taxis where (each.lowBattery = false and each.isAvailable and each.isWandering));
	    }
	}

	action create_electric_taxis_batch(int how_many) {
	    int to_create <- max(0, how_many);
	    if (to_create > 0) {
	        create electricCars number: to_create returns: created_taxis {
	            initialCrossroad <- one_of(crossroads where !(each.crossroadsNoInitialLocation));
	            self.location <- initialCrossroad.location;
	            targetCrossroads <- one_of(crossroads where !(each.crossroadsNoInitialLocation));
	            max_acceleration <- 5 / 3.6;
	            max_speed <- 70.0;
	            proba_block_node <- 0.0;
	            proba_respect_priorities <- 1.0 - rnd(200 / 1000);
	            proba_respect_stops <- [1.0];
	            proba_use_linked_road <- 0.0;
	            right_side_driving <- true;
	            speed_coeff <- 1.0 - (rnd(600) / 1000);
	            thresholdStucked <- float((1 + rnd(5)) #mn);
	            vehicle_length <- rnd(2.5, 4.0);
	            probabilityBreakdown <- 0.000005;
	            carStopInAZebraCrossing <- false;
	            carStopInAYield <- false;
	            carStopInAStop <- false;
	            carStopInAElectricRecharge <- false;
	            soc <- rnd(0.2000, 0.8000);
	            list<string> types <- ["CCS2", "Type2", "ChaDeMo"];
	            typeConnector <- one_of(types);
	        }
	        ask created_taxis { do initialize; }
	    }
	    do refresh_taxi_registry;
	}

	action remove_electric_taxis_batch(int how_many) {
	    int to_remove <- max(0, how_many);
	    if (to_remove > 0) {
	        list<electricCars> preferred <- electricCars where (
	            each != nil and !dead(each) and each.isAvailable and each.isWandering and empty(each.passengers) and empty(each.passengersToPickUp)
	        );
	        list<electricCars> others <- electricCars where (each != nil and !dead(each) and !(each in preferred));
	        list<electricCars> candidates <- preferred + others;
	        int removed <- 0;
	        loop cab over: candidates {
	            if (removed >= to_remove) { break; }
	            if (cab = nil or dead(cab)) { continue; }
	            if (!(cab.isAvailable and cab.isWandering and empty(cab.passengers) and empty(cab.passengersToPickUp))) {
	                ask cab { do fallback_complete_trip_and_release_taxi("fleet_resize_down"); }
	            }
	            ask cab { do die; }
	            removed <- removed + 1;
	        }
	    }
	    do refresh_taxi_registry;
	}

	action sync_electric_taxi_fleet_with_setting {
	    int desired <- max(0, numberOfElectricCars);
	    int current <- length(electricCars);
	    if (desired > current) {
	        do create_electric_taxis_batch(desired - current);
	    } else if (desired < current) {
	        do remove_electric_taxis_batch(current - desired);
	    } else {
	        do refresh_taxi_registry;
	    }
	}

	// Export one agent with all exposed attributes to CSV (callable from Interactive Console)
	action export_agent(agent a) {
	    if (a = nil) {
	        write "export_agent: nil agent, nothing exported.";
	    } else {
	        list<string> attrs <- species_of(a).attributes;
	        string agent_name <- string(a.name);
	        string species_name <- string(species_of(a).name);
	        save ["agent_name", "species", "attribute", "value"] to: agent_export_file format: "csv" rewrite: true;
	        loop attr over: attrs {
	            save [agent_name, species_name, attr, string(a get attr)] to: agent_export_file format: "csv" rewrite: false;
	        }
	        write "export_agent: exported " + length(attrs) + " attributes for " + agent_name + " to " + agent_export_file;
	    }
	}

	// Convenience helper to export multiple agents in long CSV format
	action export_agents(list<agent> agents_to_export) {
	    if (agents_to_export = nil or empty(agents_to_export)) {
	        write "export_agents: empty list, nothing exported.";
	    } else {
	        int exported_agents <- 0;
	        int exported_rows <- 0;
	        save ["agent_name", "species", "attribute", "value"] to: agent_export_file format: "csv" rewrite: true;
	        loop a over: agents_to_export {
	            if (a != nil) {
	                list<string> attrs <- species_of(a).attributes;
	                string agent_name <- string(a.name);
	                string species_name <- string(species_of(a).name);
	                loop attr over: attrs {
	                    save [agent_name, species_name, attr, string(a get attr)] to: agent_export_file format: "csv" rewrite: false;
	                    exported_rows <- exported_rows + 1;
	                }
	                exported_agents <- exported_agents + 1;
	            }
	        }
	        write "export_agents: exported " + exported_agents + " agents and " + exported_rows + " attribute rows to " + agent_export_file;
	    }
	}

	// Interactive route probes using GAMA's own graph/path operators.
	// Intended to be called from the Interactive Console for map debugging.
	crossroads probe_crossroad_by_id(int crossroad_id) {
	    list<crossroads> matches <- crossroads where (each.index = crossroad_id);
	    if (empty(matches)) { return nil; }
	    return matches[0];
	}

	action ensure_route_probe_header {
	    if (!route_probe_header_written) {
	        save [
	            "mode",
	            "origin_id",
	            "origin_name",
	            "origin_x",
	            "origin_y",
	            "target_id",
	            "target_name",
	            "target_x",
	            "target_y",
	            "origin_eligible",
	            "target_eligible",
	            "direct_path_found",
	            "route_kind",
	            "attempts",
	            "selected_origin_id",
	            "selected_origin_name",
	            "selected_origin_x",
	            "selected_origin_y",
	            "selected_target_id",
	            "selected_target_name",
	            "selected_target_x",
	            "selected_target_y",
	            "selected_path_found",
	            "started_without_helper_path"
	        ] to: route_probe_file format: "csv" rewrite: true;
	        route_probe_header_written <- true;
	    }
	}

	action reset_route_probe_report {
	    route_probe_header_written <- false;
	    do ensure_route_probe_header;
	    write "reset_route_probe_report: header written to " + route_probe_file;
	}

	action export_gama_walk_probe(int origin_id, int target_id) {
	    do ensure_route_probe_header;
	    crossroads origin_probe <- probe_crossroad_by_id(origin_id);
	    crossroads target_probe <- probe_crossroad_by_id(target_id);
	    bool origin_eligible <- (origin_probe != nil and (origin_probe.isStreet or origin_probe.isZebraCrossing));
	    bool target_eligible <- (target_probe != nil and (target_probe.isStreet or target_probe.isZebraCrossing));
	    crossroads selected_origin <- origin_probe;
	    crossroads selected_target <- target_probe;
	    path direct_path <- nil;
	    path selected_path <- nil;
	    bool direct_path_found <- false;
	    bool selected_path_found <- false;
	    bool started_without_helper_path <- false;
	    int attempts <- 0;
	    string route_kind <- "failed_after_retries";

	    if (origin_eligible and target_eligible) {
	        attempts <- 1;
	        direct_path <- path_between(streetsNetwork, origin_probe, target_probe);
	        direct_path_found <- (direct_path != nil);
	        if (direct_path_found) {
	            selected_path <- direct_path;
	            selected_path_found <- true;
	            route_kind <- "first_try_success";
	        }
	    }

	    save [
	        "walking",
	        origin_id,
	        (origin_probe = nil or origin_probe.name = nil) ? "" : origin_probe.name,
	        (origin_probe = nil) ? 0.0 : origin_probe.location.x,
	        (origin_probe = nil) ? 0.0 : origin_probe.location.y,
	        target_id,
	        (target_probe = nil or target_probe.name = nil) ? "" : target_probe.name,
	        (target_probe = nil) ? 0.0 : target_probe.location.x,
	        (target_probe = nil) ? 0.0 : target_probe.location.y,
	        origin_eligible,
	        target_eligible,
	        direct_path_found,
	        route_kind,
	        max(1, attempts),
	        (selected_origin = nil) ? -1 : selected_origin.index,
	        (selected_origin = nil or selected_origin.name = nil) ? "" : selected_origin.name,
	        (selected_origin = nil) ? 0.0 : selected_origin.location.x,
	        (selected_origin = nil) ? 0.0 : selected_origin.location.y,
	        (selected_target = nil) ? -1 : selected_target.index,
	        (selected_target = nil or selected_target.name = nil) ? "" : selected_target.name,
	        (selected_target = nil) ? 0.0 : selected_target.location.x,
	        (selected_target = nil) ? 0.0 : selected_target.location.y,
	        selected_path_found,
	        started_without_helper_path
	    ] to: route_probe_file format: "csv" rewrite: false;

	    write "export_gama_walk_probe: " + origin_id + " -> " + target_id + " => " + route_kind + " (attempts=" + max(1, attempts) + ")";
	}

	action export_gama_road_probe(int origin_id, int target_id) {
	    do ensure_route_probe_header;
	    crossroads origin_probe <- probe_crossroad_by_id(origin_id);
	    crossroads target_probe <- probe_crossroad_by_id(target_id);
	    bool origin_eligible <- (origin_probe != nil and !origin_probe.isStreet and !origin_probe.crossroadsNoInitialLocation);
	    bool target_eligible <- (target_probe != nil and !target_probe.isStreet and !target_probe.crossroadsNoInitialLocation);
	    crossroads selected_origin <- origin_probe;
	    crossroads selected_target <- target_probe;
	    path direct_path <- nil;
	    path selected_path <- nil;
	    bool direct_path_found <- false;
	    bool selected_path_found <- false;
	    int attempts <- 0;
	    string route_kind <- "failed_after_retries";

	    if (origin_eligible and target_eligible) {
	        attempts <- 1;
	        direct_path <- path_between(roadsNetwork, origin_probe, target_probe);
	        direct_path_found <- (direct_path != nil);
	        if (direct_path_found) {
	            selected_path <- direct_path;
	            selected_path_found <- true;
	            route_kind <- "first_try_success";
	        }
	    }

	    save [
	        "car",
	        origin_id,
	        (origin_probe = nil or origin_probe.name = nil) ? "" : origin_probe.name,
	        (origin_probe = nil) ? 0.0 : origin_probe.location.x,
	        (origin_probe = nil) ? 0.0 : origin_probe.location.y,
	        target_id,
	        (target_probe = nil or target_probe.name = nil) ? "" : target_probe.name,
	        (target_probe = nil) ? 0.0 : target_probe.location.x,
	        (target_probe = nil) ? 0.0 : target_probe.location.y,
	        origin_eligible,
	        target_eligible,
	        direct_path_found,
	        route_kind,
	        max(1, attempts),
	        (selected_origin = nil) ? -1 : selected_origin.index,
	        (selected_origin = nil or selected_origin.name = nil) ? "" : selected_origin.name,
	        (selected_origin = nil) ? 0.0 : selected_origin.location.x,
	        (selected_origin = nil) ? 0.0 : selected_origin.location.y,
	        (selected_target = nil) ? -1 : selected_target.index,
	        (selected_target = nil or selected_target.name = nil) ? "" : selected_target.name,
	        (selected_target = nil) ? 0.0 : selected_target.location.x,
	        (selected_target = nil) ? 0.0 : selected_target.location.y,
	        selected_path_found,
	        false
	    ] to: route_probe_file format: "csv" rewrite: false;

	    write "export_gama_road_probe: " + origin_id + " -> " + target_id + " => " + route_kind + " (attempts=" + max(1, attempts) + ")";
	}

	action export_gama_route_probe(string mode_label, int origin_id, int target_id) {
	    string normalized_mode <- lower_case(mode_label);
	    if (normalized_mode = "walking" or normalized_mode = "walk" or normalized_mode = "pedestrian") {
	        do export_gama_walk_probe(origin_id, target_id);
	    } else if (normalized_mode = "car" or normalized_mode = "road" or normalized_mode = "driving") {
	        do export_gama_road_probe(origin_id, target_id);
	    } else {
	        write "export_gama_route_probe: unsupported mode '" + mode_label + "'. Use walking or car.";
	    }
	}

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
	    
	    do create_electric_taxis_batch(numberOfElectricCars);
    
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
    Population generation helpers: normalize labels, build synthetic blueprints, and instantiate households.
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

string canonical_household_structure_label(string raw_label) {
    if (raw_label = nil or raw_label = "") { return "other"; }
    if ((raw_label as string) in ["single_female_under_65", "single_male_under_65", "single_female_65_plus", "single_male_65_plus", "single_parent_minor_25", "single_parent_all_children_25_plus", "couple_without_children", "couple_with_minor_25", "couple_all_children_25_plus", "family_with_minor_25_and_other_persons", "other", "hard_constraint_fallback"]) {
        return raw_label as string;
    }
    string ht <- lower_case(raw_label as string);

    if (ht = lower_case("Hogar con una mujer sola menor de 65 años")
        or ht = lower_case("Hogar con una mujer sola menor de 65 anos")
        or ht = lower_case("Hogar con una mujer sola menor de 65 a?os")) {
        return "single_female_under_65";
    }
    if (ht = lower_case("Hogar con un hombre solo menor de 65 años")
        or ht = lower_case("Hogar con un hombre solo menor de 65 anos")
        or ht = lower_case("Hogar con un hombre solo menor de 65 a?os")) {
        return "single_male_under_65";
    }
    if (ht = lower_case("Hogar con una mujer sola de 65 años o más")
        or ht = lower_case("Hogar con una mujer sola de 65 anos o mas")
        or ht = lower_case("Hogar con una mujer sola de 65 a?os o m?s")) {
        return "single_female_65_plus";
    }
    if (ht = lower_case("Hogar con un hombre solo de 65 años o más")
        or ht = lower_case("Hogar con un hombre solo de 65 anos o mas")
        or ht = lower_case("Hogar con un hombre solo de 65 a?os o m?s")) {
        return "single_male_65_plus";
    }
    if (ht = lower_case("Hogar con un solo progenitor que convive con algún hijo menor de 25 años")
        or ht = lower_case("Hogar con un solo progenitor que convive con algun hijo menor de 25 anos")
        or ht = lower_case("Hogar con un solo progenitor que convive con alg?n hijo menor de 25 a?os")) {
        return "single_parent_minor_25";
    }
    if (ht = lower_case("Hogar con un solo progenitor que convive con todos sus hijos de 25 años o más")
        or ht = lower_case("Hogar con un solo progenitor que convive con todos sus hijos de 25 anos o mas")
        or ht = lower_case("Hogar con un solo progenitor que convive con todos sus hijos de 25 a?os o m?s")) {
        return "single_parent_all_children_25_plus";
    }
    if (ht = lower_case("Hogar formado por pareja sin hijos")) {
        return "couple_without_children";
    }
    if (ht = lower_case("Hogar formado por pareja con hijos en donde algún hijo es menor de 25 años")
        or ht = lower_case("Hogar formado por pareja con hijos en donde algun hijo es menor de 25 anos")
        or ht = lower_case("Hogar formado por pareja con hijos en donde alg?n hijo es menor de 25 a?os")) {
        return "couple_with_minor_25";
    }
    if (ht = lower_case("Hogar formado por pareja con hijos en donde todos los hijos de 25 años o más")
        or ht = lower_case("Hogar formado por pareja con hijos en donde todos los hijos de 25 anos o mas")
        or ht = lower_case("Hogar formado por pareja con hijos en donde todos los hijos de 25 a?os o m?s")) {
        return "couple_all_children_25_plus";
    }
    if (ht = lower_case("Hogar formado por pareja o un solo progenitor que convive con algún hijo menor de 25 años y otra(s) persona(s)")
        or ht = lower_case("Hogar formado por pareja o un solo progenitor que convive con algun hijo menor de 25 anos y otra(s) persona(s)")
        or ht = lower_case("Hogar formado por pareja o un solo progenitor que convive con alg?n hijo menor de 25 a?os y otra(s) persona(s)")) {
        return "family_with_minor_25_and_other_persons";
    }
    return "other";
}

bool household_type_has_minor_25(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "single_parent_minor_25"
        or ht = "couple_with_minor_25"
        or ht = "family_with_minor_25_and_other_persons";
}

bool household_type_all_children_25p(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "single_parent_all_children_25_plus"
        or ht = "couple_all_children_25_plus";
}

bool household_type_is_single_parent(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "single_parent_minor_25"
        or ht = "single_parent_all_children_25_plus";
}

bool household_type_is_couple(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "couple_without_children"
        or ht = "couple_with_minor_25"
        or ht = "couple_all_children_25_plus";
}

bool household_type_has_children(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "single_parent_minor_25"
        or ht = "single_parent_all_children_25_plus"
        or ht = "couple_with_minor_25"
        or ht = "couple_all_children_25_plus"
        or ht = "family_with_minor_25_and_other_persons";
}

bool household_type_has_other_persons(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "family_with_minor_25_and_other_persons";
}

bool household_type_is_single_person_structure(string household_type_label) {
    string ht <- canonical_household_structure_label(household_type_label);
    return ht = "single_female_under_65"
        or ht = "single_male_under_65"
        or ht = "single_female_65_plus"
        or ht = "single_male_65_plus";
}

action set_partner_links(Person first_partner, Person second_partner) {
    if (first_partner != nil and second_partner != nil and first_partner != second_partner) {
        first_partner.partner <- second_partner;
        second_partner.partner <- first_partner;
    }
}

action attach_child_to_parent(Person parent, Person child) {
    if (parent != nil and child != nil) {
        if (parent.children = nil) { parent.children <- []; }
        if (!(child in parent.children)) {
            parent.children <- parent.children + child;
        }
        if (parent.gender = "male") {
            if (child.father = nil) { child.father <- parent; }
            else if (child.father != parent and child.mother = nil) { child.mother <- parent; }
        } else {
            if (child.mother = nil) { child.mother <- parent; }
            else if (child.mother != parent and child.father = nil) { child.father <- parent; }
        }
        if (child.father != nil and child.mother != nil and child.father = child.mother) {
            if (child.father.gender = "male") { child.mother <- nil; }
            else if (child.father.gender = "female") { child.father <- nil; }
            else { child.mother <- nil; }
        }
    }
}

action assign_single_parent_family(Person parent, list<Person> children_list) {
    if (parent != nil and children_list != nil) {
        loop child over: children_list {
            if (child != nil) {
                if (parent.gender = "male") {
                    child.father <- parent;
                    child.mother <- nil;
                } else {
                    child.mother <- parent;
                    child.father <- nil;
                }
                do attach_child_to_parent(parent: parent, child: child);
            }
        }
    }
}

action assign_couple_family(Person first_parent, Person second_parent, list<Person> children_list) {
    if (first_parent != nil and second_parent != nil and children_list != nil) {
        do set_partner_links(first_partner: first_parent, second_partner: second_parent);
        loop child over: children_list {
            if (child != nil) {
                child.father <- nil;
                child.mother <- nil;
                do attach_child_to_parent(parent: first_parent, child: child);
                do attach_child_to_parent(parent: second_parent, child: child);
                if (child.father != nil and child.father.gender = "female" and child.mother = nil) {
                    child.mother <- child.father;
                    child.father <- nil;
                }
                if (child.mother != nil and child.mother.gender = "male" and child.father = nil) {
                    child.father <- child.mother;
                    child.mother <- nil;
                }
            }
        }
    }
}

action cleanup_household_members(list<Person> members_to_remove) {
    if (members_to_remove != nil) {
        loop p over: members_to_remove {
            if (p != nil and !dead(p)) {
                ask p { do die; }
            }
        }
    }
}

list<Person> build_hard_fallback_household_members(int hh_size_i, Household household) {
    list<Person> fallback_members <- [];
    int safe_size <- max(1, hh_size_i);
    loop i from: 1 to: safe_size {
        Person p <- getPerson(nil, 18, 99, nil, hardConstraintFallbackType, household, false);
        fallback_members <- fallback_members + [p];
    }
    return fallback_members;
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

float age_range_midpoint(string age_range_label) {
    if (age_range_label = nil or age_range_label = "") { return 0.0; }
    if (!(age_range_label contains "-")) { return 0.0; }
    list<string> parts <- split_with(age_range_label, "-");
    if (length(parts) < 2) { return 0.0; }
    int lo <- parts[0] as_int 10;
    int hi <- parts[1] as_int 10;
    return (lo + hi) / 2.0;
}

string couple_age_gap_bucket(float gap_years) {
    float g <- max(0.0, gap_years);
    if (g < 5.0) { return "0-4"; }
    if (g < 10.0) { return "5-9"; }
    if (g < 15.0) { return "10-14"; }
    return "15+";
}

int sibling_min_compatible_age(list<Person> siblings, int base_min_age) {
    int lower_bound <- base_min_age;
    if (siblings != nil and !empty(siblings)) {
        loop s over: siblings {
            if (s != nil) {
                lower_bound <- max(lower_bound, s.age - 10);
            }
        }
    }
    return max(base_min_age, lower_bound);
}

int sibling_max_compatible_age(list<Person> siblings, int base_max_age) {
    int upper_bound <- base_max_age;
    if (siblings != nil and !empty(siblings)) {
        loop s over: siblings {
            if (s != nil) {
                upper_bound <- min(upper_bound, s.age + 10);
            }
        }
    }
    return min(base_max_age, upper_bound);
}

int sample_age_with_bias(int minAge, int maxAge, string bias_mode) {
    if (maxAge < minAge) { maxAge <- minAge; }
    if (maxAge = minAge) { return minAge; }
    float u <- rnd(1.0);
    float normalized <- u;
    string mode <- (bias_mode = nil or bias_mode = "") ? "uniform" : lower_case(bias_mode);
    if (mode = "min_medium") {
        normalized <- u ^ 2.0;
    } else if (mode = "min_strong") {
        normalized <- u ^ 3.0;
    } else if (mode = "max_medium") {
        normalized <- 1.0 - ((1.0 - u) ^ 2.0);
    } else if (mode = "max_strong") {
        normalized <- 1.0 - ((1.0 - u) ^ 3.0);
    }
    return minAge + int(round(normalized * (maxAge - minAge)));
}

int gap_min_for_bucket(string gap_bucket) {
    if (gap_bucket = "5-9") { return 5; }
    if (gap_bucket = "10-14") { return 10; }
    if (gap_bucket = "15+") { return 15; }
    return 0;
}

int gap_max_for_bucket(string gap_bucket) {
    if (gap_bucket = "0-4") { return 4; }
    if (gap_bucket = "5-9") { return 9; }
    if (gap_bucket = "10-14") { return 14; }
    return 20;
}

int couple_gap_bucket_rank(string gap_bucket) {
    if (gap_bucket = "0-4") { return 0; }
    if (gap_bucket = "5-9") { return 1; }
    if (gap_bucket = "10-14") { return 2; }
    return 3;
}

map<string, int> age_range_bounds(string age_range_label) {
    if (age_range_label = nil or age_range_label = "" or !(age_range_label contains "-")) {
        return map<string, int>(map([
            "lo" :: -1,
            "hi" :: -1
        ]));
    }
    list<string> parts <- split_with(age_range_label, "-");
    if (length(parts) < 2) {
        return map<string, int>(map([
            "lo" :: -1,
            "hi" :: -1
        ]));
    }
    int lo <- parts[0] as_int 10;
    int hi <- parts[1] as_int 10;
    if (hi < lo) {
        int tmp <- lo;
        lo <- hi;
        hi <- tmp;
    }
    return map<string, int>(map([
        "lo" :: lo,
        "hi" :: hi
    ]));
}

map<string, int> gap_interval_for_age_range(int anchor_age, string age_range_label) {
    map<string, int> bounds <- age_range_bounds(age_range_label);
    int lo <- (bounds["lo"] = nil) ? -1 : bounds["lo"];
    int hi <- (bounds["hi"] = nil) ? -1 : bounds["hi"];
    if (lo < 0 or hi < 0) {
        return map<string, int>(map([
            "min_gap" :: 999,
            "max_gap" :: -1
        ]));
    }
    int min_gap <- 0;
    if (anchor_age < lo) { min_gap <- lo - anchor_age; }
    else if (anchor_age > hi) { min_gap <- anchor_age - hi; }
    int max_gap <- max(abs(anchor_age - lo), abs(anchor_age - hi));
    return map<string, int>(map([
        "min_gap" :: min_gap,
        "max_gap" :: max_gap
    ]));
}

int gap_interval_distance(int min_gap, int max_gap, int bucket_min, int bucket_max) {
    if (max_gap < bucket_min) { return bucket_min - max_gap; }
    if (min_gap > bucket_max) { return min_gap - bucket_max; }
    return 0;
}

bool age_range_intersects_gap_bucket(int anchor_age, string age_range_label, string gap_bucket) {
    map<string, int> interval <- gap_interval_for_age_range(anchor_age, age_range_label);
    int min_gap <- (interval["min_gap"] = nil) ? 999 : interval["min_gap"];
    int max_gap <- (interval["max_gap"] = nil) ? -1 : interval["max_gap"];
    if (max_gap < min_gap) { return false; }
    int bucket_min <- gap_min_for_bucket(gap_bucket);
    int bucket_max <- gap_max_for_bucket(gap_bucket);
    return !(max_gap < bucket_min or min_gap > bucket_max);
}

string representative_gap_bucket_for_range(int anchor_age, string age_range_label, string target_gap_bucket) {
    map<string, int> interval <- gap_interval_for_age_range(anchor_age, age_range_label);
    int min_gap <- (interval["min_gap"] = nil) ? 999 : interval["min_gap"];
    int max_gap <- (interval["max_gap"] = nil) ? -1 : interval["max_gap"];
    if (max_gap < min_gap) { return target_gap_bucket; }
    string best_bucket <- "15+";
    int best_rank_distance <- 999;
    int best_interval_distance <- 999;
    loop b over: ["0-4", "5-9", "10-14", "15+"] {
        int rank_distance <- abs(couple_gap_bucket_rank(b) - couple_gap_bucket_rank(target_gap_bucket));
        int interval_distance <- gap_interval_distance(min_gap, max_gap, gap_min_for_bucket(b), gap_max_for_bucket(b));
        if (
            rank_distance < best_rank_distance
            or (rank_distance = best_rank_distance and interval_distance < best_interval_distance)
        ) {
            best_bucket <- b;
            best_rank_distance <- rank_distance;
            best_interval_distance <- interval_distance;
        }
    }
    return best_bucket;
}

float couple_gap_target_share(string gap_bucket) {
    float v <- (coupleAgeGapProbabilities[gap_bucket] = nil) ? 0.0 : max(0.0, coupleAgeGapProbabilities[gap_bucket] as float);
    if (v > 0.0) { return v; }
    return 0.25;
}

int total_observed_couple_gap_count {
    int total <- 0;
    loop b over: ["0-4", "5-9", "10-14", "15+"] {
        total <- total + ((coupleGapObservedCounts[b] = nil) ? 0 : coupleGapObservedCounts[b]);
    }
    return total;
}

map<string, float> choose_couple_gap_target_weights_with_deficit(map<string, float> partner_probs, int anchor_age, bool has_children, int parental_min_age) {
    map<string, float> final_weights <- map<string, float>(map([]));
    list<string> feasible_buckets <- [];
    loop b over: ["0-4", "5-9", "10-14", "15+"] {
        map<string, float> stage_probs <- filter_partner_age_probabilities_by_gap_set(partner_probs, anchor_age, [b]);
        if (stage_probs = nil or empty(keys(stage_probs))) {
            continue;
        }
        if (has_children) {
            map<string, float> plausible_probs <- map<string, float>(map([]));
            loop label over: keys(stage_probs) {
                string age_label <- label as string;
                if (age_label != nil and age_label contains "-") {
                    list<string> parts <- split_with(age_label, "-");
                    if (length(parts) >= 2) {
                        int lo <- parts[0] as_int 10;
                        int hi <- parts[1] as_int 10;
                        if (max(lo, parental_min_age) <= hi) {
                            plausible_probs[age_label] <- stage_probs[label];
                        }
                    }
                }
            }
            if (plausible_probs = nil or empty(keys(plausible_probs))) {
                continue;
            }
        }
        feasible_buckets <- feasible_buckets + [b];
    }
    if (empty(feasible_buckets)) { return final_weights; }

    float base_sum <- 0.0;
    loop b over: feasible_buckets {
        float base_share <- couple_gap_target_share(b);
        final_weights[b] <- max(0.0, base_share);
        base_sum <- base_sum + max(0.0, base_share);
    }
    if (base_sum <= 0.0) {
        loop b over: feasible_buckets {
            final_weights[b] <- 1.0 / length(feasible_buckets);
        }
        return final_weights;
    }
    loop b over: feasible_buckets { final_weights[b] <- final_weights[b] / base_sum; }
    return final_weights;
}

string choose_couple_gap_bucket_with_quota(map<string, float> feasible_weights) {
    if (feasible_weights = nil or empty(keys(feasible_weights))) { return nil; }
    list<string> feasible_buckets <- keys(feasible_weights);
    map<string, float> adjusted <- map<string, float>(map([]));

    bool has_remaining <- false;
    loop b over: feasible_buckets {
        int target <- (coupleGapQuotaTargetCounts[b] = nil) ? 0 : coupleGapQuotaTargetCounts[b];
        int used <- (coupleGapQuotaUsedCounts[b] = nil) ? 0 : coupleGapQuotaUsedCounts[b];
        if (target - used > 0) { has_remaining <- true; }
    }

    if (has_remaining) {
        loop b over: feasible_buckets {
            float base_w <- max(0.0001, feasible_weights[b] as float);
            int target <- (coupleGapQuotaTargetCounts[b] = nil) ? 0 : coupleGapQuotaTargetCounts[b];
            int used <- (coupleGapQuotaUsedCounts[b] = nil) ? 0 : coupleGapQuotaUsedCounts[b];
            int remaining <- max(0, target - used);
            float q_w <- 0.1 + remaining;
            adjusted[b] <- base_w * q_w;
        }
    } else {
        int min_overflow <- 999999;
        loop b over: feasible_buckets {
            int target <- (coupleGapQuotaTargetCounts[b] = nil) ? 0 : coupleGapQuotaTargetCounts[b];
            int used <- (coupleGapQuotaUsedCounts[b] = nil) ? 0 : coupleGapQuotaUsedCounts[b];
            int overflow <- max(0, used - target);
            min_overflow <- min(min_overflow, overflow);
        }
        loop b over: feasible_buckets {
            float base_w <- max(0.0001, feasible_weights[b] as float);
            int target <- (coupleGapQuotaTargetCounts[b] = nil) ? 0 : coupleGapQuotaTargetCounts[b];
            int used <- (coupleGapQuotaUsedCounts[b] = nil) ? 0 : coupleGapQuotaUsedCounts[b];
            int overflow <- max(0, used - target);
            float over_w <- 1.0 / (1.0 + max(0, overflow - min_overflow));
            adjusted[b] <- base_w * over_w;
        }
    }

    string selected <- rnd_choice(adjusted);
    if (selected = nil or selected = "") { selected <- rnd_choice(feasible_weights); }
    return selected;
}

map<string, float> build_stage3_guided_partner_probs(map<string, float> partner_probs, int anchor_age, string target_gap_bucket) {
    map<string, float> guided <- map<string, float>(map([]));
    if (partner_probs = nil or empty(keys(partner_probs))) { return guided; }
    int total_observed <- total_observed_couple_gap_count;
    float observed_denom <- max(1.0, total_observed as float);
    loop label over: keys(partner_probs) {
        string age_label <- (label = nil) ? "" : (label as string);
        if (age_label = "" or !(age_label in age_ranges)) { continue; }
        float base_p <- max(0.0, partner_probs[label] as float);
        if (base_p <= 0.0) { continue; }
        map<string, int> interval <- gap_interval_for_age_range(anchor_age, age_label);
        int min_gap <- (interval["min_gap"] = nil) ? 999 : interval["min_gap"];
        int max_gap <- (interval["max_gap"] = nil) ? -1 : interval["max_gap"];
        if (max_gap < min_gap) { continue; }
        string candidate_bucket <- representative_gap_bucket_for_range(anchor_age, age_label, target_gap_bucket);
        int d <- gap_interval_distance(min_gap, max_gap, gap_min_for_bucket(target_gap_bucket), gap_max_for_bucket(target_gap_bucket));
        float distance_weight <- 0.2;
        if (d = 0) { distance_weight <- 1.0; }
        else if (d <= 3) { distance_weight <- 0.7; }
        else if (d <= 6) { distance_weight <- 0.4; }

        float target_share <- couple_gap_target_share(candidate_bucket);
        int observed_count <- (coupleGapObservedCounts[candidate_bucket] = nil) ? 0 : coupleGapObservedCounts[candidate_bucket];
        float observed_share <- observed_count / observed_denom;
        float deficit <- target_share - observed_share;
        float deficit_weight <- 1.0 + (1.2 * deficit);
        deficit_weight <- max(0.3, deficit_weight);
        deficit_weight <- min(2.2, deficit_weight);

        float score <- base_p * distance_weight * deficit_weight;
        if (score > 0.0) {
            guided[age_label] <- score;
        }
    }
    float total <- 0.0;
    loop label over: keys(guided) { total <- total + max(0.0, guided[label] as float); }
    if (total <= 0.0) { return map<string, float>(map([])); }
    loop label over: keys(guided) { guided[label] <- max(0.0, guided[label] as float) / total; }
    return guided;
}

bool is_gap_bucket_allowed_for_stage(string bucket, int stage, string target_gap_bucket, list<string> stage2_gap_buckets) {
    if (stage = 1) { return bucket = target_gap_bucket; }
    if (stage = 2) { return bucket in stage2_gap_buckets; }
    return true;
}

map<string, int> stage_allowed_gap_range(int stage, string target_gap_bucket, list<string> stage2_gap_buckets) {
    int gmin <- 0;
    int gmax <- 120;
    if (stage = 1) {
        gmin <- gap_min_for_bucket(target_gap_bucket);
        gmax <- gap_max_for_bucket(target_gap_bucket);
    } else if (stage = 2 and stage2_gap_buckets != nil and !empty(stage2_gap_buckets)) {
        gmin <- 120;
        gmax <- 0;
        loop b over: stage2_gap_buckets {
            gmin <- min(gmin, gap_min_for_bucket(b));
            gmax <- max(gmax, gap_max_for_bucket(b));
        }
        if (gmin > gmax) {
            gmin <- 0;
            gmax <- 120;
        }
    }
    return map<string, int>(map([
        "min" :: gmin,
        "max" :: gmax
    ]));
}

map<string, int> choose_partner_age_for_stage(
    int anchor_age,
    int minAge,
    int maxAge,
    int stage,
    string target_gap_bucket,
    list<string> stage2_gap_buckets
) {
    int try_limit <- 20;
    map<string, int> allowed_range <- stage_allowed_gap_range(stage, target_gap_bucket, stage2_gap_buckets);
    int allowed_min_gap <- (allowed_range["min"] = nil) ? 0 : allowed_range["min"];
    int allowed_max_gap <- (allowed_range["max"] = nil) ? 120 : allowed_range["max"];
    int best_age <- -1;
    int best_distance <- 999;
    string best_bucket <- nil;
    int tries <- 0;
    loop i from: 1 to: try_limit {
        tries <- tries + 1;
        int candidate_age <- rnd(minAge, maxAge, 1);
        int gap_value <- abs(anchor_age - candidate_age);
        bool in_allowed_range <- (gap_value >= allowed_min_gap and gap_value <= allowed_max_gap);
        string candidate_bucket <- couple_age_gap_bucket(gap_value);
        bool allowed_bucket <- is_gap_bucket_allowed_for_stage(candidate_bucket, stage, target_gap_bucket, stage2_gap_buckets);
        int distance_rank <- abs(couple_gap_bucket_rank(candidate_bucket) - couple_gap_bucket_rank(target_gap_bucket));
        int distance_score <- (distance_rank * 100) + abs(gap_value - ((gap_min_for_bucket(target_gap_bucket) + gap_max_for_bucket(target_gap_bucket)) / 2));
        if (distance_score < best_distance) {
            best_distance <- distance_score;
            best_age <- candidate_age;
            best_bucket <- candidate_bucket;
        }
        if ((stage <= 2 and in_allowed_range and allowed_bucket) or (stage = 3 and allowed_bucket)) {
            return map<string, int>(map([
                "age" :: candidate_age,
                "tries" :: tries
            ]));
        }
    }
    if (best_age < 0) { best_age <- rnd(minAge, maxAge, 1); }
    return map<string, int>(map([
        "age" :: best_age,
        "tries" :: tries
    ]));
}

action register_household_hard_fallback_reason(string reason_label) {
    string reason_key <- (reason_label = nil or reason_label = "") ? "unknown" : reason_label;
    int current <- (householdHardFallbackReasonCounts[reason_key] = nil) ? 0 : householdHardFallbackReasonCounts[reason_key];
    householdHardFallbackReasonCounts[reason_key] <- current + 1;
}

bool sibling_soft_window_available(list<Person> sibling_refs, int minAge, int maxAge, int max_gap_years) {
    if (sibling_refs = nil or empty(sibling_refs)) { return true; }
    int sibling_min <- 1000;
    int sibling_max <- -1;
    loop s over: sibling_refs {
        if (s != nil) {
            sibling_min <- min(sibling_min, s.age);
            sibling_max <- max(sibling_max, s.age);
        }
    }
    if (sibling_max < 0) { return true; }
    int allowed_min <- max(minAge, sibling_min - max_gap_years);
    int allowed_max <- min(maxAge, sibling_max + max_gap_years);
    return allowed_max >= allowed_min;
}

int choose_soft_relax_stage_for_siblings(list<Person> sibling_refs, int minAge, int maxAge) {
    if (sibling_refs = nil or empty(sibling_refs)) { return 1; }
    if (sibling_soft_window_available(sibling_refs, minAge, maxAge, 10)) { return 1; }
    if (sibling_soft_window_available(sibling_refs, minAge, maxAge, 15)) { return 2; }
    return 3;
}

Person create_person_with_soft_relaxation(
    string sex,
    int minAge,
    int maxAge,
    list<Person> children,
    string householdType,
    Household household,
    list<Person> sibling_refs,
    string stage1_bias,
    string stage2_bias,
    string stage3_bias
) {
    int stage <- choose_soft_relax_stage_for_siblings(sibling_refs, minAge, maxAge);
    string bias1 <- (stage1_bias = nil or stage1_bias = "") ? "uniform" : stage1_bias;
    string bias2 <- (stage2_bias = nil or stage2_bias = "") ? "uniform" : stage2_bias;
    string bias3 <- (stage3_bias = nil or stage3_bias = "") ? "uniform" : stage3_bias;
    Person p <- nil;
    if (stage = 1) {
        p <- getPersonWithBias(sex, minAge, maxAge, children, householdType, household, bias1);
    } else if (stage = 2) {
        p <- getPersonWithBias(sex, minAge, maxAge, children, householdType, household, bias2);
        personCreationSoftRelaxStage1Count <- max(0, personCreationSoftRelaxStage1Count - 1);
        personCreationSoftRelaxStage2Count <- personCreationSoftRelaxStage2Count + 1;
    } else {
        p <- getPersonWithBias(sex, minAge, maxAge, children, householdType, household, bias3);
        personCreationSoftRelaxStage1Count <- max(0, personCreationSoftRelaxStage1Count - 1);
        personCreationSoftRelaxStage3Count <- personCreationSoftRelaxStage3Count + 1;
    }
    return p;
}

list<string> couple_gap_stage2_buckets(string target_gap_bucket) {
    if (target_gap_bucket = "0-4") { return ["0-4", "5-9"]; }
    if (target_gap_bucket = "5-9") { return ["5-9", "0-4", "10-14"]; }
    if (target_gap_bucket = "10-14") { return ["10-14", "5-9", "15+"]; }
    return ["15+", "10-14"];
}

map<string, float> filter_partner_age_probabilities_by_gap_set(map<string, float> partner_probs, int anchor_age, list<string> allowed_gap_buckets) {
    map<string, float> filtered <- map<string, float>(map([]));
    if (partner_probs = nil or empty(keys(partner_probs)) or allowed_gap_buckets = nil or empty(allowed_gap_buckets)) {
        return filtered;
    }
    loop label over: keys(partner_probs) {
        string age_label <- (label = nil) ? "" : (label as string);
        if (age_label != "" and age_label in age_ranges) {
            bool matches <- false;
            loop gb over: allowed_gap_buckets {
                if (!matches and age_range_intersects_gap_bucket(anchor_age, age_label, gb)) {
                    matches <- true;
                }
            }
            if (matches) {
                filtered[age_label] <- max(0.0, partner_probs[label] as float);
            }
        }
    }
    float total <- 0.0;
    loop label over: keys(filtered) { total <- total + max(0.0, filtered[label] as float); }
    if (total <= 0.0) { return map<string, float>(map([])); }
    loop label over: keys(filtered) { filtered[label] <- max(0.0, filtered[label] as float) / total; }
    return filtered;
}

bool household_members_respect_hard_constraints(string household_type_label, list<Person> members) {
    if (members = nil or empty(members)) { return false; }
    string ht <- canonical_household_structure_label(household_type_label);

    if (ht = "single_female_under_65") {
        if (length(members) != 1) { return false; }
        return members[0].gender = "female" and members[0].age >= 18 and members[0].age <= 64;
    }
    if (ht = "single_male_under_65") {
        if (length(members) != 1) { return false; }
        return members[0].gender = "male" and members[0].age >= 18 and members[0].age <= 64;
    }
    if (ht = "single_female_65_plus") {
        if (length(members) != 1) { return false; }
        return members[0].gender = "female" and members[0].age >= 65;
    }
    if (ht = "single_male_65_plus") {
        if (length(members) != 1) { return false; }
        return members[0].gender = "male" and members[0].age >= 65;
    }

    int min_parent_gap <- minimum_parental_age_gap_from_distribution;
    list<Person> linked_children <- [];
    loop p over: members {
        if (p != nil and (p.father != nil or p.mother != nil)) {
            linked_children <- linked_children + [p];
        }
    }

    if (household_type_all_children_25p(ht)) {
        if (empty(linked_children)) { return false; }
        loop c over: linked_children {
            if (c.age < 25) { return false; }
        }
    }
    if (household_type_has_minor_25(ht)) {
        bool has_minor <- false;
        loop c over: linked_children {
            if (c.age <= 24) { has_minor <- true; }
        }
        if (!has_minor) { return false; }
    }
    if (household_type_has_children(ht)) {
        if (empty(linked_children)) { return false; }
        loop c over: linked_children {
            if (c.father != nil and c.father in members and c.father.age < c.age + min_parent_gap) { return false; }
            if (c.mother != nil and c.mother in members and c.mother.age < c.age + min_parent_gap) { return false; }
        }
    }
    return true;
}

int minimum_parental_age_gap_from_distribution {
    int best_gap <- 15;
    if (motherAgeProbabilities != nil and !empty(keys(motherAgeProbabilities))) {
        int found_min <- 999;
        loop k over: keys(motherAgeProbabilities) {
            float p <- (motherAgeProbabilities[k] = nil) ? 0.0 : (motherAgeProbabilities[k] as float);
            string label <- (k = nil) ? "" : (k as string);
            if (p > 0.0 and label contains "-") {
                list<string> parts <- split_with(label, "-");
                if (length(parts) >= 2) {
                    int lo <- parts[0] as_int 10;
                    found_min <- min(found_min, lo);
                }
            }
        }
        if (found_min < 999) { best_gap <- found_min; }
    }
    return max(12, best_gap);
}

map<string, float> filter_partner_age_probabilities_by_gap(map<string, float> partner_probs, int anchor_age, string target_gap_bucket) {
    map<string, float> filtered <- map<string, float>(map([]));
    if (partner_probs = nil or empty(keys(partner_probs))) { return filtered; }
    loop label over: keys(partner_probs) {
        string age_label <- (label = nil) ? "" : (label as string);
        if (age_label != "" and age_label in age_ranges) {
            if (age_range_intersects_gap_bucket(anchor_age, age_label, target_gap_bucket)) {
                filtered[age_label] <- max(0.0, partner_probs[label] as float);
            }
        }
    }
    float total <- 0.0;
    loop label over: keys(filtered) { total <- total + max(0.0, filtered[label] as float); }
    if (total <= 0.0) { return map<string, float>(map([])); }
    loop label over: keys(filtered) { filtered[label] <- max(0.0, filtered[label] as float) / total; }
    return filtered;
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

bool blueprint_is_valid(map<string, string> bp) {
    if (bp = nil) { return false; }
    string uid <- (bp["uid"] = nil) ? "" : (bp["uid"] as string);
    string bp_gender <- (bp["gender"] = nil) ? "" : normalize_gender_label(bp["gender"] as string);
    string bp_age <- (bp["age_range"] = nil) ? "" : (bp["age_range"] as string);
    return uid != "" and (bp_gender = "male" or bp_gender = "female") and (bp_age in age_ranges);
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

map<string, string> pull_population_blueprint(string requested_gender, int minAge, int maxAge, bool strict_gender) {
    blueprintPullAttempts <- blueprintPullAttempts + 1;
    if (populationBlueprintAvailable <= 0) {
        blueprintMisses <- blueprintMisses + 1;
        return nil;
    }
    if (populationBlueprintBuckets = nil or empty(keys(populationBlueprintBuckets))) {
        do rebuild_population_blueprint_index;
    }

    string requested <- (requested_gender = nil or requested_gender = "") ? "" : normalize_gender_label(requested_gender);
    list<string> age_candidates <- collect_intersecting_age_ranges(minAge, maxAge);
    map<string, string> chosen <- nil;

    if (requested != "") {
        list<string> exact_keys <- build_blueprint_bucket_keys([requested], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(exact_keys);
        if (blueprint_is_valid(chosen)) {
            blueprintExactMatches <- blueprintExactMatches + 1;
            return chosen;
        }
    }
    if (!blueprint_is_valid(chosen) and requested != "" and strict_gender) {
        list<string> gender_only_keys <- build_blueprint_bucket_keys([requested], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(gender_only_keys);
        if (blueprint_is_valid(chosen)) {
            blueprintGenderOnlyMatches <- blueprintGenderOnlyMatches + 1;
            return chosen;
        }
    }
    if (!blueprint_is_valid(chosen)) {
        list<string> age_only_keys <- build_blueprint_bucket_keys(["male", "female"], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(age_only_keys);
        if (blueprint_is_valid(chosen)) {
            blueprintAgeOnlyMatches <- blueprintAgeOnlyMatches + 1;
            return chosen;
        }
    }
    if (!blueprint_is_valid(chosen) and requested != "" and !strict_gender) {
        list<string> gender_only_keys <- build_blueprint_bucket_keys([requested], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(gender_only_keys);
        if (blueprint_is_valid(chosen)) {
            blueprintGenderOnlyMatches <- blueprintGenderOnlyMatches + 1;
            return chosen;
        }
    }
    if (!blueprint_is_valid(chosen)) {
        list<string> any_keys <- build_blueprint_bucket_keys(["male", "female"], age_candidates);
        chosen <- pop_blueprint_from_bucket_keys(any_keys);
        if (blueprint_is_valid(chosen)) {
            blueprintAnyMatches <- blueprintAnyMatches + 1;
            return chosen;
        }
    }

    blueprintMisses <- blueprintMisses + 1;
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
    if (partnerProbabilities = nil or empty(keys(partnerProbabilities))) {
        string fallbackAgeRange <- partner.age_range;
        if ((split_with(fallbackAgeRange, "-")[0] as_int 10) >= 60 and ((normalized_partner_gender = "male" and husbandAgeCoupleProbabilities["60-99"] != nil) or (normalized_partner_gender != "male" and wifeAgeCoupleProbabilities["60-99"] != nil))) {
            fallbackAgeRange <- "60-99";
        }
        partnerProbabilities <- (normalized_partner_gender = "male")
            ? husbandAgeCoupleProbabilities[fallbackAgeRange]
            : wifeAgeCoupleProbabilities[fallbackAgeRange];
    }
    if (partnerProbabilities = nil or empty(keys(partnerProbabilities))) {
        partnerProbabilities <- map<string, float>(map([partner.age_range :: 1.0]));
    }

    bool has_children <- partner.children != nil and !empty(partner.children);
    int parental_min_age <- 0;
    if (has_children) {
        int oldestChildAge <- max(partner.children collect each.age);
        int minimumParentGap <- minimum_parental_age_gap_from_distribution;
        parental_min_age <- oldestChildAge + minimumParentGap;
    }
    map<string, float> dynamicGapTargetWeights <- choose_couple_gap_target_weights_with_deficit(
        partnerProbabilities,
        partner.age,
        has_children,
        parental_min_age
    );
    if (dynamicGapTargetWeights = nil or empty(keys(dynamicGapTargetWeights))) {
        return nil;
    }
    string targetGapBucket <- choose_couple_gap_bucket_with_quota(dynamicGapTargetWeights);
    if (targetGapBucket = nil or targetGapBucket = "") { targetGapBucket <- "0-4"; }
    list<string> stage2GapBuckets <- couple_gap_stage2_buckets(targetGapBucket);

    int selectedStage <- 0;
    map<string, float> effectivePartnerProbabilities <- map<string, float>(map([]));
    map<string, float> stage1Probs <- filter_partner_age_probabilities_by_gap_set(partnerProbabilities, partner.age, [targetGapBucket]);
    map<string, float> stage2Probs <- filter_partner_age_probabilities_by_gap_set(partnerProbabilities, partner.age, stage2GapBuckets);
    map<string, float> stage3Probs <- build_stage3_guided_partner_probs(partnerProbabilities, partner.age, targetGapBucket);
    if (stage3Probs = nil or empty(keys(stage3Probs))) {
        stage3Probs <- partnerProbabilities;
    }
    loop stageCandidate over: [1, 2, 3] {
        map<string, float> stage_probs <- map<string, float>(map([]));
        if (stageCandidate = 1) {
            stage_probs <- stage1Probs;
        } else if (stageCandidate = 2) {
            stage_probs <- stage2Probs;
        } else {
            stage_probs <- stage3Probs;
        }
        if (stage_probs = nil or empty(keys(stage_probs))) {
            continue;
        }
        if (has_children) {
            map<string, float> plausible_probs <- map<string, float>(map([]));
            loop label over: keys(stage_probs) {
                string age_label <- label as string;
                if (age_label != nil and age_label contains "-") {
                    list<string> age_parts <- split_with(age_label, "-");
                    if (length(age_parts) >= 2) {
                        int lo <- age_parts[0] as_int 10;
                        int hi <- age_parts[1] as_int 10;
                        if (max(lo, parental_min_age) <= hi) {
                            plausible_probs[age_label] <- stage_probs[label];
                        }
                    }
                }
            }
            if (plausible_probs = nil or empty(keys(plausible_probs))) {
                continue;
            }
            stage_probs <- plausible_probs;
        }
        selectedStage <- stageCandidate;
        effectivePartnerProbabilities <- stage_probs;
        break;
    }
    if (selectedStage = 0 or effectivePartnerProbabilities = nil or empty(keys(effectivePartnerProbabilities))) {
        return nil;
    }

    string selectedAgeRange <- rnd_choice(effectivePartnerProbabilities);
    if (selectedAgeRange = nil or selectedAgeRange = "") { selectedAgeRange <- partner.age_range; }
    if (selectedAgeRange = nil or selectedAgeRange = "" or !(selectedAgeRange contains "-")) {
        return nil;
    }
    list<string> ageParts <- split_with(selectedAgeRange, "-");
    if (length(ageParts) < 2) { return nil; }
    int minAge <- ageParts[0] as_int 10;
    int maxAge <- ageParts[1] as_int 10;
    if (has_children) {
        minAge <- max(minAge, parental_min_age);
    }
    if (maxAge < minAge) { return nil; }
    map<string, int> sampled_partner <- choose_partner_age_for_stage(
        partner.age,
        minAge,
        maxAge,
        selectedStage,
        targetGapBucket,
        stage2GapBuckets
    );
    int chosen_partner_age <- (sampled_partner["age"] = nil) ? rnd(minAge, maxAge, 1) : sampled_partner["age"];
    int chosen_tries <- (sampled_partner["tries"] = nil) ? 1 : sampled_partner["tries"];
    if (chosen_tries > 1) {
        coupleGapSampleRetries <- coupleGapSampleRetries + (chosen_tries - 1);
    }
    Person newPartner <- getPersonWithBias(sex, chosen_partner_age, chosen_partner_age, nil, "", household, "uniform");
    if (newPartner = nil) { return nil; }
    if (selectedStage = 2) {
        personCreationSoftRelaxStage1Count <- max(0, personCreationSoftRelaxStage1Count - 1);
        personCreationSoftRelaxStage2Count <- personCreationSoftRelaxStage2Count + 1;
    } else if (selectedStage = 3) {
        personCreationSoftRelaxStage1Count <- max(0, personCreationSoftRelaxStage1Count - 1);
        personCreationSoftRelaxStage3Count <- personCreationSoftRelaxStage3Count + 1;
    }
    coupleGapTargetBucketHits <- coupleGapTargetBucketHits + 1;
    string achievedGapBucket <- couple_age_gap_bucket(abs(partner.age - newPartner.age));
    if (achievedGapBucket = targetGapBucket) {
        coupleGapAchievedOnTarget <- coupleGapAchievedOnTarget + 1;
    } else {
        coupleGapQuotaSpilloverCount <- coupleGapQuotaSpilloverCount + 1;
    }
    int achievedCount <- (coupleGapObservedCounts[achievedGapBucket] = nil) ? 0 : coupleGapObservedCounts[achievedGapBucket];
    coupleGapObservedCounts[achievedGapBucket] <- achievedCount + 1;
    int quota_used <- (coupleGapQuotaUsedCounts[achievedGapBucket] = nil) ? 0 : coupleGapQuotaUsedCounts[achievedGapBucket];
    coupleGapQuotaUsedCounts[achievedGapBucket] <- quota_used + 1;
    newPartner.partner <- partner;
    partner.partner <- newPartner;
    if (partner.children != nil and !empty(partner.children)) {
        if (newPartner.children = nil) { newPartner.children <- []; }
        loop child over: partner.children {
            if (child != nil and !(child in newPartner.children)) {
                newPartner.children <- newPartner.children + child;
            }
            if (child != nil) {
                if (newPartner.gender = "male") {
                    if (child.father = nil) { child.father <- newPartner; }
                    else if (child.father != newPartner and child.mother = nil) { child.mother <- newPartner; }
                } else {
                    if (child.mother = nil) { child.mother <- newPartner; }
                    else if (child.mother != newPartner and child.father = nil) { child.father <- newPartner; }
                }
                if (child.father != nil and child.mother != nil and child.father = child.mother) {
                    if (child.father.gender = "male") { child.mother <- nil; }
                    else if (child.father.gender = "female") { child.father <- nil; }
                    else { child.mother <- nil; }
                }
            }
        }
    }
    return newPartner;
}

string household_person_rectification_signature(Person p) {
    if (p = nil) { return ""; }
    list<string> child_names <- [];
    if (p.children != nil) {
        loop c over: p.children {
            if (c != nil) {
                string child_name <- (c.name = nil) ? string(c) : c.name;
                child_names <- child_names + [child_name];
            }
        }
    }
    string father_name <- (p.father = nil or p.father.name = nil) ? "" : p.father.name;
    string mother_name <- (p.mother = nil or p.mother.name = nil) ? "" : p.mother.name;
    string partner_name <- (p.partner = nil or p.partner.name = nil) ? "" : p.partner.name;
    string home_ref <- (p.living_place = nil) ? "" : string(p.living_place);
    return father_name + "|" + mother_name + "|" + partner_name + "|" + home_ref + "|" + string(child_names);
}

string household_person_father_ref(Person p) {
    return (p = nil or p.father = nil or p.father.name = nil) ? "" : p.father.name;
}

string household_person_mother_ref(Person p) {
    return (p = nil or p.mother = nil or p.mother.name = nil) ? "" : p.mother.name;
}

string household_person_partner_ref(Person p) {
    return (p = nil or p.partner = nil or p.partner.name = nil) ? "" : p.partner.name;
}

string household_person_home_ref(Person p) {
    return (p = nil or p.living_place = nil) ? "" : string(p.living_place);
}

string household_person_children_ref(Person p) {
    if (p = nil or p.children = nil) { return ""; }
    list<string> child_names <- [];
    loop c over: p.children {
        if (c != nil) {
            string child_name <- (c.name = nil) ? string(c) : c.name;
            child_names <- child_names + [child_name];
        }
    }
    return string(child_names);
}

list<Person> infer_household_core_members(string household_type_label, list<Person> members) {
    list<Person> core <- [];
    if (members = nil or empty(members)) { return core; }
    string ht <- canonical_household_structure_label(household_type_label);
    bool is_single_parent <- household_type_is_single_parent(ht);
    bool is_couple <- household_type_is_couple(ht);
    bool has_children <- household_type_has_children(ht);
    bool has_other_persons <- household_type_has_other_persons(ht);

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
    if (empty(core) and household_type_is_single_person_structure(ht)) { core <- [members[0]]; }
    if (empty(core)) { core <- list<Person>(members); }
    return core;
}

list<Person> enforce_household_relationships(string household_type_label, list<Person> members) {
    if (members = nil or empty(members)) { return members; }

    string ht <- canonical_household_structure_label(household_type_label);
    bool is_single_parent <- household_type_is_single_parent(ht);
    bool is_couple <- household_type_is_couple(ht);
    bool has_children <- household_type_has_children(ht);

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
                    else if (child.father != parent1 and child.mother = nil) { child.mother <- parent1; }
                } else {
                    if (child.mother = nil) { child.mother <- parent1; }
                    else if (child.mother != parent1 and child.father = nil) { child.father <- parent1; }
                }

                if (parent2.gender = "male") {
                    if (child.father = nil) { child.father <- parent2; }
                    else if (child.father != parent2 and child.mother = nil) { child.mother <- parent2; }
                } else {
                    if (child.mother = nil) { child.mother <- parent2; }
                    else if (child.mother != parent2 and child.father = nil) { child.father <- parent2; }
                }

                if (!(child in parent1.children)) { parent1.children <- parent1.children + child; }
                if (!(child in parent2.children)) { parent2.children <- parent2.children + child; }
                if (child.father != nil and child.mother != nil and child.father = child.mother) {
                    if (child.father.gender = "male") { child.mother <- nil; }
                    else if (child.father.gender = "female") { child.father <- nil; }
                    else { child.mother <- nil; }
                }
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
        if (child.father != nil and child.mother != nil and child.father = child.mother) {
            if (child.father.gender = "male") { child.mother <- nil; }
            else if (child.father.gender = "female") { child.father <- nil; }
            else { child.mother <- nil; }
        }
        if (child.father != nil and child.father.gender = "female" and child.mother = nil) {
            child.mother <- child.father;
            child.father <- nil;
        }
        if (child.mother != nil and child.mother.gender = "male" and child.father = nil) {
            child.father <- child.mother;
            child.mother <- nil;
        }
    }

    return members;
}

int createFamilies(int s) {
    blueprintRejectedNonIntersectingAgeCount <- 0;
    personCreationSoftRelaxStage1Count <- 0;
    personCreationSoftRelaxStage2Count <- 0;
    personCreationSoftRelaxStage3Count <- 0;
    householdHardFallbackCount <- 0;
    hardConstraintViolationsFinal <- 0;
    householdHardFallbackReasonCounts <- map<string, int>(map([]));
    coupleGapTargetBucketHits <- 0;
    coupleGapAchievedOnTarget <- 0;
    coupleGapSampleRetries <- 0;
    coupleGapQuotaSpilloverCount <- 0;
    coupleGapObservedCounts <- map<string, int>(map([
        "0-4" :: 0,
        "5-9" :: 0,
        "10-14" :: 0,
        "15+" :: 0
    ]));
    coupleGapQuotaTargetCounts <- map<string, int>(map([
        "0-4" :: 0,
        "5-9" :: 0,
        "10-14" :: 0,
        "15+" :: 0
    ]));
    coupleGapQuotaUsedCounts <- map<string, int>(map([
        "0-4" :: 0,
        "5-9" :: 0,
        "10-14" :: 0,
        "15+" :: 0
    ]));

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
    int local_fillers_added <- 0;
    int local_overflow_removed <- 0;
    int local_size_adjusted_households <- 0;
    int local_fill_adjusted_households <- 0;
    int local_overflow_adjusted_households <- 0;
    int local_postprocess_rectified_households <- 0;
    list<string> local_postprocess_rectified_person_refs <- [];
    int local_postprocess_home_rectified_households <- 0;
    int local_postprocess_home_rectified_persons <- 0;
    int local_postprocess_partner_rectified_households <- 0;
    int local_postprocess_partner_rectified_persons <- 0;
    int local_postprocess_father_rectified_households <- 0;
    int local_postprocess_father_rectified_persons <- 0;
    int local_postprocess_mother_rectified_households <- 0;
    int local_postprocess_mother_rectified_persons <- 0;
    int local_postprocess_children_rectified_households <- 0;
    int local_postprocess_children_rectified_persons <- 0;
    int local_hard_violations_final <- 0;
    list<map<string, string>> household_requests_with_children <- [];
    list<map<string, string>> household_requests_without_children <- [];
    list<map<string, string>> household_requests_other <- [];
    loop hh_size over: household_plan {
        int hh_size_i <- int(hh_size);
        string numMembers <- household_label_from_size(hh_size_i);
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

        string householdTypeKey <- canonical_household_structure_label(selectedHouseholdType);
        map<string, string> household_request <- map<string, string>(map([
            "size" :: string(hh_size_i),
            "num_members" :: numMembers,
            "household_type" :: selectedHouseholdType
        ]));
        if (householdTypeKey = "other") {
            household_requests_other <- household_requests_other + [household_request];
        } else if (household_type_has_children(householdTypeKey)) {
            household_requests_with_children <- household_requests_with_children + [household_request];
        } else {
            household_requests_without_children <- household_requests_without_children + [household_request];
        }
    }

    list<map<string, string>> household_generation_plan <- shuffle(household_requests_with_children)
        + shuffle(household_requests_without_children)
        + shuffle(household_requests_other);

    // Couple age-gap quota plan (global control, similar to household planning)
    int planned_couple_households <- 0;
    loop rq over: household_generation_plan {
        string rq_type <- canonical_household_structure_label(rq["household_type"]);
        if (household_type_is_couple(rq_type)) {
            planned_couple_households <- planned_couple_households + 1;
        }
    }
    list<string> couple_gap_categories <- ["0-4", "5-9", "10-14", "15+"];
    map<string, float> couple_gap_target_probs <- map<string, float>(map([]));
    float couple_gap_prob_sum <- 0.0;
    loop gb over: couple_gap_categories {
        float gp <- max(0.0, couple_gap_target_share(gb));
        couple_gap_target_probs[gb] <- gp;
        couple_gap_prob_sum <- couple_gap_prob_sum + gp;
    }
    if (couple_gap_prob_sum <= 0.0) {
        loop gb over: couple_gap_categories { couple_gap_target_probs[gb] <- 0.25; }
    } else {
        loop gb over: couple_gap_categories { couple_gap_target_probs[gb] <- couple_gap_target_probs[gb] / couple_gap_prob_sum; }
    }
    coupleGapQuotaTargetCounts <- largest_remainder_counts(couple_gap_target_probs, couple_gap_categories, planned_couple_households);
    coupleGapQuotaUsedCounts <- map<string, int>(map([
        "0-4" :: 0,
        "5-9" :: 0,
        "10-14" :: 0,
        "15+" :: 0
    ]));

    // Keep requested generation order by household complexity, but randomize district/house assignment independently.
    map<string, float> valid_district_probabilities <- map<string, float>(map([]));
    list<string> valid_district_categories <- [];
    float valid_district_prob_sum <- 0.0;
    loop dk over: keys(districtDistributionProbabilities) {
        string district_key <- dk as string;
        list<building> district_houses <- residentialBuildingsByDistrict[district_key];
        if (district_houses != nil and !empty(district_houses)) {
            float p <- max(0.0, districtDistributionProbabilities[dk] as float);
            if (p > 0.0) {
                valid_district_probabilities[district_key] <- p;
                valid_district_categories <- valid_district_categories + [district_key];
                valid_district_prob_sum <- valid_district_prob_sum + p;
            }
        }
    }
    if (empty(valid_district_categories)) {
        loop dk over: keys(residentialBuildingsByDistrict) {
            string district_key <- dk as string;
            list<building> district_houses <- residentialBuildingsByDistrict[district_key];
            if (district_houses != nil and !empty(district_houses)) {
                valid_district_probabilities[district_key] <- 1.0;
                valid_district_categories <- valid_district_categories + [district_key];
            }
        }
        valid_district_prob_sum <- max(1.0, length(valid_district_categories));
    }
    if (valid_district_prob_sum > 0.0) {
        loop d over: valid_district_categories {
            valid_district_probabilities[d] <- max(0.0, valid_district_probabilities[d] as float) / valid_district_prob_sum;
        }
    }

    map<string, int> district_household_counts <- largest_remainder_counts(
        valid_district_probabilities,
        valid_district_categories,
        length(household_generation_plan)
    );
    list<string> district_assignment_plan <- [];
    loop d over: valid_district_categories {
        int cnt <- (district_household_counts[d] = nil) ? 0 : district_household_counts[d];
        loop i from: 1 to: cnt {
            district_assignment_plan <- district_assignment_plan + [d];
        }
    }
    loop while: length(district_assignment_plan) < length(household_generation_plan) {
        district_assignment_plan <- district_assignment_plan + [rnd_choice(valid_district_probabilities)];
    }
    district_assignment_plan <- shuffle(district_assignment_plan);

    map<string, list<building>> district_houses_shuffled <- map<string, list<building>>(map([]));
    map<string, int> district_house_cursor <- map<string, int>(map([]));
    loop d over: valid_district_categories {
        list<building> district_houses <- residentialBuildingsByDistrict[d];
        if (district_houses = nil) { district_houses <- []; }
        district_houses_shuffled[d] <- shuffle(district_houses);
        district_house_cursor[d] <- 0;
    }
    int district_assignment_cursor <- 0;

    households <- [];
    loop household_request over: household_generation_plan {
        int hh_size_i <- household_request["size"] as_int 10;
        string numMembers <- household_request["num_members"];
        string selectedHouseholdType <- household_request["household_type"];
        int household_fillers_added <- 0;
        int household_overflow_removed <- 0;
        if (length(Person) >= numPeople) { break; }
        create Household number: 1 returns: household {
            numberPersons <- numMembers;
            string householdDistrict <- "";
            if (district_assignment_cursor < length(district_assignment_plan)) {
                householdDistrict <- district_assignment_plan[district_assignment_cursor];
                district_assignment_cursor <- district_assignment_cursor + 1;
            }
            if (householdDistrict = nil or householdDistrict = "") {
                householdDistrict <- rnd_choice(districtDistributionProbabilities);
            }
            list<building> district_houses <- district_houses_shuffled[householdDistrict];
            if (district_houses = nil or empty(district_houses)) {
                district_houses <- residentialBuildingsByDistrict[householdDistrict];
                if (district_houses != nil and !empty(district_houses)) {
                    district_houses <- shuffle(district_houses);
                    district_houses_shuffled[householdDistrict] <- district_houses;
                    district_house_cursor[householdDistrict] <- 0;
                }
            }
            if (district_houses != nil and !empty(district_houses)) {
                int house_cursor <- (district_house_cursor[householdDistrict] = nil) ? 0 : district_house_cursor[householdDistrict];
                if (house_cursor >= length(district_houses)) {
                    house_cursor <- 0;
                    district_houses <- shuffle(district_houses);
                    district_houses_shuffled[householdDistrict] <- district_houses;
                }
                house <- district_houses[house_cursor];
                district_house_cursor[householdDistrict] <- house_cursor + 1;
            } else {
                house <- one_of(residential_buildings where (each.district = householdDistrict));
            }
            district <- householdDistrict;
            if (house = nil and verbose_population_logs) {
                write "Warning: no residential building found for district " + householdDistrict + " (household " + self + ").";
            }
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
                else if (_entry_norm contains "mostol" or _entry_norm contains "stol") { leganesEntry <- "Mostoles"; }
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
        if (!empty(household)) {
            household[0].houseNumber <- "House_" + string(generated_households + 1);
        }

        string generatedHouseholdType <- selectedHouseholdType;
        string hardFallbackReason <- "";
        bool hardFallbackApplied <- false;
        string ht <- canonical_household_structure_label(selectedHouseholdType);
        bool has_minor_25 <- household_type_has_minor_25(ht);
        bool all_children_25p <- household_type_all_children_25p(ht);
        bool is_single_parent <- household_type_is_single_parent(ht);
        bool is_couple <- household_type_is_couple(ht);
        bool has_children <- household_type_has_children(ht);
        bool has_other_persons <- household_type_has_other_persons(ht);

        list<Person> householdMembers <- [];

        if (numMembers = "1 persona") {
            Person person <- nil;
            if (ht = "single_female_under_65") {
                person <- getPerson("female", 18, 64, nil, selectedHouseholdType, household[0], false);
            } else if (ht = "single_male_under_65") {
                person <- getPerson("male", 18, 64, nil, selectedHouseholdType, household[0], false);
            } else if (ht = "single_female_65_plus") {
                person <- getPerson("female", 65, 99, nil, selectedHouseholdType, household[0], false);
            } else if (ht = "single_male_65_plus") {
                person <- getPerson("male", 65, 99, nil, selectedHouseholdType, household[0], false);
            } else {
                person <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
            }
            householdMembers <- householdMembers + person;
        } else if (numMembers = "2 personas") {
            if (is_single_parent and has_minor_25) {
                Person child <- getPerson(nil, 0, 24, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child]);
                householdMembers <- householdMembers + child + parent;
            } else if (is_single_parent and all_children_25p) {
                Person child <- create_person_with_soft_relaxation(nil, 25, 44, nil, selectedHouseholdType, household[0], nil, "min_strong", "min_medium", "uniform");
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child]);
                householdMembers <- householdMembers + child + parent;
            } else if (is_couple and !has_children) {
                Person person <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person partner <- matchPartner(person, household[0]);
                do set_partner_links(first_partner: person, second_partner: partner);
                householdMembers <- householdMembers + person + partner;
            } else {
                Person person1 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                Person person2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
                householdMembers <- householdMembers + person1 + person2;
            }
        } else if (numMembers = "3 personas") {
            if (is_single_parent and has_minor_25) {
                Person child1 <- create_person_with_soft_relaxation(nil, 0, 24, nil, selectedHouseholdType, household[0], nil, "max_medium", "max_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person parent <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child1, child2]);
                householdMembers <- householdMembers + child1 + child2 + parent;
            } else if (is_single_parent and all_children_25p) {
                Person child1 <- create_person_with_soft_relaxation(nil, 25, 44, [], selectedHouseholdType, household[0], nil, "min_strong", "min_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 25, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person parent <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child1, child2]);
                householdMembers <- householdMembers + child1 + child2 + parent;
            } else if (is_couple and has_children and has_minor_25) {
                Person child <- getPerson(nil, 0, 24, nil, selectedHouseholdType, household[0], false);
                Person partner1 <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                do assign_couple_family(first_parent: partner1, second_parent: partner2, children_list: [child]);
                householdMembers <- householdMembers + child + partner1 + partner2;
            } else if (is_couple and has_children and all_children_25p) {
                Person child <- create_person_with_soft_relaxation(nil, 25, 44, [], selectedHouseholdType, household[0], nil, "min_strong", "min_medium", "uniform");
                Person partner1 <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                do assign_couple_family(first_parent: partner1, second_parent: partner2, children_list: [child]);
                householdMembers <- householdMembers + child + partner1 + partner2;
            } else if (has_other_persons and has_minor_25) {
                Person child <- getPerson(nil, 0, 24, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child]);
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
                Person child1 <- create_person_with_soft_relaxation(nil, 0, 24, nil, selectedHouseholdType, household[0], nil, "max_medium", "max_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person child3 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1, child2], "max_medium", "max_medium", "uniform");
                Person parent <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child1, child2, child3]);
                householdMembers <- householdMembers + child1 + child2 + child3 + parent;
            } else if (is_single_parent and all_children_25p) {
                Person child1 <- create_person_with_soft_relaxation(nil, 25, 44, nil, selectedHouseholdType, household[0], nil, "min_strong", "min_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 25, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person child3 <- create_person_with_soft_relaxation(nil, 25, child1.age, nil, selectedHouseholdType, household[0], [child1, child2], "max_medium", "max_medium", "uniform");
                Person parent <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child1, child2, child3]);
                householdMembers <- householdMembers + child1 + child2 + child3 + parent;
            } else if (is_couple and has_children and has_minor_25) {
                Person child1 <- getPerson(nil, 0, 24, nil, selectedHouseholdType, household[0], false);
                Person child2 <- getPerson(nil, 25, 35, nil, selectedHouseholdType, household[0], true);
                Person partner1 <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                do assign_couple_family(first_parent: partner1, second_parent: partner2, children_list: [child1, child2]);
                householdMembers <- householdMembers + child1 + child2 + partner1 + partner2;
            } else if (is_couple and has_children and all_children_25p) {
                Person child1 <- create_person_with_soft_relaxation(nil, 25, 44, nil, selectedHouseholdType, household[0], nil, "min_strong", "min_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 25, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person partner1 <- getPerson(nil, 18, 99, [child1, child2], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                do assign_couple_family(first_parent: partner1, second_parent: partner2, children_list: [child1, child2]);
                householdMembers <- householdMembers + child1 + child2 + partner1 + partner2;
            } else if (has_other_persons and has_minor_25) {
                Person child <- getPerson(nil, 0, 24, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner <- matchPartner(parent, household[0]);
                do assign_couple_family(first_parent: parent, second_parent: partner, children_list: [child]);
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
                Person child1 <- create_person_with_soft_relaxation(nil, 0, 24, nil, selectedHouseholdType, household[0], nil, "max_medium", "max_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person child3 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1, child2], "max_medium", "max_medium", "uniform");
                Person child4 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1, child2, child3], "max_medium", "max_medium", "uniform");
                Person parent <- getPerson(nil, 18, 99, [child1, child2, child3, child4], selectedHouseholdType, household[0], false);
                do assign_single_parent_family(parent: parent, children_list: [child1, child2, child3, child4]);
                householdMembers <- householdMembers + child1 + child2 + child3 + child4 + parent;
            } else if (is_couple and has_children and has_minor_25) {
                Person child1 <- create_person_with_soft_relaxation(nil, 0, 24, nil, selectedHouseholdType, household[0], nil, "max_medium", "max_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person child3 <- create_person_with_soft_relaxation(nil, 0, child1.age, nil, selectedHouseholdType, household[0], [child1, child2], "max_medium", "max_medium", "uniform");
                Person partner1 <- getPerson(nil, 18, child1.age + 25, [child1, child2, child3], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                do assign_couple_family(first_parent: partner1, second_parent: partner2, children_list: [child1, child2, child3]);
                householdMembers <- householdMembers + child1 + child2 + child3 + partner1 + partner2;
            } else if (is_couple and has_children and all_children_25p) {
                Person child1 <- create_person_with_soft_relaxation(nil, 25, 44, nil, selectedHouseholdType, household[0], nil, "min_strong", "min_medium", "uniform");
                Person child2 <- create_person_with_soft_relaxation(nil, 25, child1.age, nil, selectedHouseholdType, household[0], [child1], "max_medium", "max_medium", "uniform");
                Person child3 <- create_person_with_soft_relaxation(nil, 25, child1.age, nil, selectedHouseholdType, household[0], [child1, child2], "max_medium", "max_medium", "uniform");
                Person partner1 <- getPerson(nil, 18, 99, [child1, child2, child3], selectedHouseholdType, household[0], false);
                Person partner2 <- matchPartner(partner1, household[0]);
                do assign_couple_family(first_parent: partner1, second_parent: partner2, children_list: [child1, child2, child3]);
                householdMembers <- householdMembers + child1 + child2 + child3 + partner1 + partner2;
            } else if (has_other_persons and has_minor_25) {
                Person child <- getPerson(nil, 0, 24, nil, selectedHouseholdType, household[0], false);
                Person parent <- getPerson(nil, 18, 99, [child], selectedHouseholdType, household[0], false);
                Person partner <- matchPartner(parent, household[0]);
                do assign_couple_family(first_parent: parent, second_parent: partner, children_list: [child]);
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

        bool has_nil_member <- false;
        loop hm over: householdMembers {
            if (hm = nil) { has_nil_member <- true; }
        }
        if (has_nil_member) {
            hardFallbackApplied <- true;
            hardFallbackReason <- is_couple ? "partner_hard_unsatisfied" : "member_creation_failed";
            do cleanup_household_members(householdMembers);
            householdMembers <- build_hard_fallback_household_members(hh_size_i, household[0]);
        }

        loop while: length(householdMembers) < hh_size_i {
            Person filler <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
            householdMembers <- householdMembers + filler;
            household_fillers_added <- household_fillers_added + 1;
            local_fillers_added <- local_fillers_added + 1;
        }
        loop while: length(householdMembers) > hh_size_i {
            Person overflow <- last(householdMembers);
            householdMembers <- householdMembers - overflow;
            ask overflow { do die; }
            household_overflow_removed <- household_overflow_removed + 1;
            local_overflow_removed <- local_overflow_removed + 1;
        }
        if (household_fillers_added > 0 or household_overflow_removed > 0) {
            local_size_adjusted_households <- local_size_adjusted_households + 1;
        }
        if (household_fillers_added > 0) {
            local_fill_adjusted_households <- local_fill_adjusted_households + 1;
        }
        if (household_overflow_removed > 0) {
            local_overflow_adjusted_households <- local_overflow_adjusted_households + 1;
        }

        if (!hardFallbackApplied and !household_members_respect_hard_constraints(ht, householdMembers)) {
            hardFallbackApplied <- true;
            hardFallbackReason <- "age_hard_unsatisfied";
            do cleanup_household_members(householdMembers);
            householdMembers <- build_hard_fallback_household_members(hh_size_i, household[0]);
        }

        loop while: length(householdMembers) < hh_size_i {
            Person filler2 <- getPerson(nil, 18, 99, nil, selectedHouseholdType, household[0], false);
            householdMembers <- householdMembers + filler2;
            household_fillers_added <- household_fillers_added + 1;
            local_fillers_added <- local_fillers_added + 1;
        }
        loop while: length(householdMembers) > hh_size_i {
            Person overflow2 <- last(householdMembers);
            householdMembers <- householdMembers - overflow2;
            ask overflow2 { do die; }
            household_overflow_removed <- household_overflow_removed + 1;
            local_overflow_removed <- local_overflow_removed + 1;
        }
        if (hardFallbackApplied) {
            generatedHouseholdType <- hardConstraintFallbackType;
            householdHardFallbackCount <- householdHardFallbackCount + 1;
            do register_household_hard_fallback_reason(hardFallbackReason);
        }

        household[0].numberPersons <- numMembers;
        household[0].members <- list<Person>(householdMembers);
        household[0].nucleusMemberRefs <- [];
        household[0].householdType <- selectedHouseholdType;
        household[0].householdTypeTheoretical <- selectedHouseholdType;
        household[0].householdTypeGenerated <- generatedHouseholdType;
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
            map<string, string> before_signatures <- map<string, string>(map([]));
            map<string, string> before_father_refs <- map<string, string>(map([]));
            map<string, string> before_mother_refs <- map<string, string>(map([]));
            map<string, string> before_partner_refs <- map<string, string>(map([]));
            map<string, string> before_home_refs <- map<string, string>(map([]));
            map<string, string> before_children_refs <- map<string, string>(map([]));
            loop mp over: h.members {
                if (mp != nil) {
                    string person_ref <- (mp.name = nil) ? string(mp) : mp.name;
                    before_signatures[person_ref] <- household_person_rectification_signature(mp);
                    before_father_refs[person_ref] <- household_person_father_ref(mp);
                    before_mother_refs[person_ref] <- household_person_mother_ref(mp);
                    before_partner_refs[person_ref] <- household_person_partner_ref(mp);
                    before_home_refs[person_ref] <- household_person_home_ref(mp);
                    before_children_refs[person_ref] <- household_person_children_ref(mp);
                }
            }
            list<Person> fixed_members <- enforce_household_relationships(hh_type, h.members);
            list<Person> householdCoreMembers <- infer_household_core_members(hh_type, fixed_members);
            list<string> householdCoreRefs <- [];
            bool household_rectified <- false;
            bool household_home_rectified <- false;
            bool household_partner_rectified <- false;
            bool household_father_rectified <- false;
            bool household_mother_rectified <- false;
            bool household_children_rectified <- false;
            loop fp over: fixed_members {
                if (fp != nil) {
                    string person_ref <- (fp.name = nil) ? string(fp) : fp.name;
                    string before_signature <- before_signatures[person_ref];
                    string after_signature <- household_person_rectification_signature(fp);
                    if (before_signature = nil or before_signature != after_signature) {
                        household_rectified <- true;
                        if (!(person_ref in local_postprocess_rectified_person_refs)) {
                            local_postprocess_rectified_person_refs <- local_postprocess_rectified_person_refs + [person_ref];
                        }
                    }
                    if (before_home_refs[person_ref] != household_person_home_ref(fp)) {
                        household_home_rectified <- true;
                        local_postprocess_home_rectified_persons <- local_postprocess_home_rectified_persons + 1;
                    }
                    if (before_partner_refs[person_ref] != household_person_partner_ref(fp)) {
                        household_partner_rectified <- true;
                        local_postprocess_partner_rectified_persons <- local_postprocess_partner_rectified_persons + 1;
                    }
                    if (before_father_refs[person_ref] != household_person_father_ref(fp)) {
                        household_father_rectified <- true;
                        local_postprocess_father_rectified_persons <- local_postprocess_father_rectified_persons + 1;
                    }
                    if (before_mother_refs[person_ref] != household_person_mother_ref(fp)) {
                        household_mother_rectified <- true;
                        local_postprocess_mother_rectified_persons <- local_postprocess_mother_rectified_persons + 1;
                    }
                    if (before_children_refs[person_ref] != household_person_children_ref(fp)) {
                        household_children_rectified <- true;
                        local_postprocess_children_rectified_persons <- local_postprocess_children_rectified_persons + 1;
                    }
                }
            }
            loop cp over: householdCoreMembers {
                if (cp != nil and cp.name != nil and !(cp.name in householdCoreRefs)) {
                    householdCoreRefs <- householdCoreRefs + cp.name;
                }
            }
            h.members <- fixed_members;
            h.nucleusMemberRefs <- householdCoreRefs;
            if (household_rectified) {
                local_postprocess_rectified_households <- local_postprocess_rectified_households + 1;
            }
            if (household_home_rectified) { local_postprocess_home_rectified_households <- local_postprocess_home_rectified_households + 1; }
            if (household_partner_rectified) { local_postprocess_partner_rectified_households <- local_postprocess_partner_rectified_households + 1; }
            if (household_father_rectified) { local_postprocess_father_rectified_households <- local_postprocess_father_rectified_households + 1; }
            if (household_mother_rectified) { local_postprocess_mother_rectified_households <- local_postprocess_mother_rectified_households + 1; }
            if (household_children_rectified) { local_postprocess_children_rectified_households <- local_postprocess_children_rectified_households + 1; }
        }
    }

    loop h over: households {
        string generated_type <- (h.householdTypeGenerated = nil or h.householdTypeGenerated = "") ? h.householdType : h.householdTypeGenerated;
        bool valid_hard <- household_members_respect_hard_constraints(generated_type, h.members);
        if (!valid_hard and canonical_household_structure_label(generated_type) != canonical_household_structure_label(hardConstraintFallbackType)) {
            local_hard_violations_final <- local_hard_violations_final + 1;
        }
    }

    householdSizeFillersAdded <- local_fillers_added;
    householdSizeOverflowRemoved <- local_overflow_removed;
    householdSizeAdjustedHouseholds <- local_size_adjusted_households;
    householdSizeFillAdjustedHouseholds <- local_fill_adjusted_households;
    householdSizeOverflowAdjustedHouseholds <- local_overflow_adjusted_households;
    householdPostprocessRectifiedHouseholds <- local_postprocess_rectified_households;
    householdPostprocessRectifiedPersons <- length(local_postprocess_rectified_person_refs);
    householdPostprocessHomeRectifiedHouseholds <- local_postprocess_home_rectified_households;
    householdPostprocessHomeRectifiedPersons <- local_postprocess_home_rectified_persons;
    householdPostprocessPartnerRectifiedHouseholds <- local_postprocess_partner_rectified_households;
    householdPostprocessPartnerRectifiedPersons <- local_postprocess_partner_rectified_persons;
    householdPostprocessFatherRectifiedHouseholds <- local_postprocess_father_rectified_households;
    householdPostprocessFatherRectifiedPersons <- local_postprocess_father_rectified_persons;
    householdPostprocessMotherRectifiedHouseholds <- local_postprocess_mother_rectified_households;
    householdPostprocessMotherRectifiedPersons <- local_postprocess_mother_rectified_persons;
    householdPostprocessChildrenRectifiedHouseholds <- local_postprocess_children_rectified_households;
    householdPostprocessChildrenRectifiedPersons <- local_postprocess_children_rectified_persons;
    hardConstraintViolationsFinal <- local_hard_violations_final;

    write("Household size adjustment stats | fillers added: " + householdSizeFillersAdded
        + " | overflow removed: " + householdSizeOverflowRemoved
        + " | adjusted households: " + householdSizeAdjustedHouseholds
        + " | filler households: " + householdSizeFillAdjustedHouseholds
        + " | overflow households: " + householdSizeOverflowAdjustedHouseholds);
    write("Household postprocess stats | rectified households: " + householdPostprocessRectifiedHouseholds
        + " | rectified persons: " + householdPostprocessRectifiedPersons);
    write("Household postprocess breakdown | home households: " + householdPostprocessHomeRectifiedHouseholds
        + " | home persons: " + householdPostprocessHomeRectifiedPersons
        + " | partner households: " + householdPostprocessPartnerRectifiedHouseholds
        + " | partner persons: " + householdPostprocessPartnerRectifiedPersons
        + " | father households: " + householdPostprocessFatherRectifiedHouseholds
        + " | father persons: " + householdPostprocessFatherRectifiedPersons
        + " | mother households: " + householdPostprocessMotherRectifiedHouseholds
        + " | mother persons: " + householdPostprocessMotherRectifiedPersons
        + " | children households: " + householdPostprocessChildrenRectifiedHouseholds
        + " | children persons: " + householdPostprocessChildrenRectifiedPersons);
    write("Blueprint usage stats | getPerson calls: " + populationGetPersonCalls
        + " | pull attempts: " + blueprintPullAttempts
        + " | exact: " + blueprintExactMatches
        + " | age_only: " + blueprintAgeOnlyMatches
        + " | gender_only: " + blueprintGenderOnlyMatches
        + " | any: " + blueprintAnyMatches
        + " | misses: " + blueprintMisses
        + " | fallback creations: " + blueprintFallbackPersonGenerations);
    write("Hard/soft generation stats | hard violations final: " + hardConstraintViolationsFinal
        + " | household hard fallback count: " + householdHardFallbackCount
        + " | soft stage1: " + personCreationSoftRelaxStage1Count
        + " | soft stage2: " + personCreationSoftRelaxStage2Count
        + " | soft stage3: " + personCreationSoftRelaxStage3Count
        + " | blueprint rejected non intersecting age: " + blueprintRejectedNonIntersectingAgeCount);

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

	Person getPersonWithBias(string sex, int minAge, int maxAge, list<Person> children, string householdType, Household household, string ageBiasMode) {
	    populationGetPersonCalls <- populationGetPersonCalls + 1;
	    // Adjust age limits based on the ages of provided children
	    string motherMaxAgeRange;
	    int oldestChildAge;
	    if (children != nil) {
	        // Find the oldest child's age
	        oldestChildAge <- max(children collect each.age);
	        // Choose a random maximum age range for the parent
	        motherMaxAgeRange <- rnd_choice(motherAgeProbabilities);
	        // Split the age range string into its numeric parts
	        list<string> ageRangeParts <- split_with(motherMaxAgeRange, "-");
	        // Increase minimum and maximum ages by the oldest child's age
	        minAge <- int(ageRangeParts[0]) + oldestChildAge;
	        maxAge <- int(ageRangeParts[1]) + oldestChildAge;
	    }
	
	    // Clamp age bounds to valid human age range
	    if (maxAge > 120) {
	        maxAge <- 120;
	    }
	    if (minAge > 120) {
	        minAge <- 120;
	    }
	    if (minAge < 0) {
	        minAge <- 0;
	    }
	
	    Person p;
	    string requested_gender <- (sex = nil) ? nil : normalize_gender_label(sex);
	    string hh_key <- canonical_household_structure_label(householdType);
	    bool structure_requires_gender <- hh_key = "single_female_under_65"
	        or hh_key = "single_male_under_65"
	        or hh_key = "single_female_65_plus"
	        or hh_key = "single_male_65_plus";
	    bool strict_gender <- requested_gender != nil and requested_gender != "" and structure_requires_gender;
	    map<string, string> blueprint <- pull_population_blueprint(requested_gender, minAge, maxAge, strict_gender);

	    int ageValue <- sample_age_with_bias(minAge, maxAge, ageBiasMode);
	    string raw_gender <- (requested_gender = nil or requested_gender = "") ? (rnd_choice(sexProbabilities) as string) : requested_gender;
	    string gender <- normalize_gender_label(raw_gender);
	    string ageRange <- age_ranges first_with ((split_with(each, "-")[1] as_int 10) >= ageValue);
	    if (ageRange = nil) { ageRange <- "100-120"; }
	    bool blueprint_valid <- blueprint_is_valid(blueprint);
	    bool fallback_counted <- !blueprint_valid;
	    if (!blueprint_valid) {
	        blueprintFallbackPersonGenerations <- blueprintFallbackPersonGenerations + 1;
	    }

	    if (blueprint_valid) {
	        string bp_gender <- strict_gender
	            ? requested_gender
	            : ((blueprint["gender"] = nil) ? gender : normalize_gender_label(blueprint["gender"] as string));
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
	                    blueprint_valid <- false;
	                    blueprintRejectedNonIntersectingAgeCount <- blueprintRejectedNonIntersectingAgeCount + 1;
	                } else {
	                    ageValue <- sample_age_with_bias(sample_min, sample_max, ageBiasMode);
	                    ageRange <- bp_age_range;
	                }
	            }
	        }
	        if (blueprint_valid) {
	            gender <- bp_gender;
	        }
	    }

	    if (!blueprint_valid) {
	        if (!fallback_counted) {
	            blueprintFallbackPersonGenerations <- blueprintFallbackPersonGenerations + 1;
	            fallback_counted <- true;
	        }
	        if (strict_gender and requested_gender != nil and requested_gender != "") {
	            gender <- requested_gender;
	        } else if (requested_gender != nil and requested_gender != "") {
	            gender <- requested_gender;
	        } else {
	            gender <- normalize_gender_label(rnd_choice(sexProbabilities) as string);
	        }
	        ageValue <- sample_age_with_bias(minAge, maxAge, ageBiasMode);
	        ageRange <- age_ranges first_with ((split_with(each, "-")[1] as_int 10) >= ageValue);
	        if (ageRange = nil) { ageRange <- "100-120"; }
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
	    personCreationSoftRelaxStage1Count <- personCreationSoftRelaxStage1Count + 1;
	    return p;
	}

	Person getPerson(string sex, int minAge, int maxAge, list<Person> children, string householdType, Household household, bool decreasingBias) {
	    string ageBiasMode <- decreasingBias ? "min_strong" : "uniform";
	    return self.getPersonWithBias(sex, minAge, maxAge, children, householdType, household, ageBiasMode);
	}

	// Keep electric taxi fleet synchronized with IDE parameter during runtime
	reflex sync_electric_taxi_fleet_runtime when: taxiCallCenter != nil {
	    int desired <- max(0, numberOfElectricCars);
	    int current <- length(electricCars);
	    if (current != desired) {
	        do sync_electric_taxi_fleet_with_setting;
	        if (simLogger != nil) {
	            ask simLogger {
	                do log_event("TAXI_FLEET_SYNC," + time + ",global,fleet,target:" + desired + "|current:" + length(electricCars) + ",0,0");
	            }
	        }
	    } else if (cycle mod 100 = 0) {
	        do refresh_taxi_registry;
	    }
	}
}
    
/**
 * Date/time helper agent.
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
        'database'    :: '../includes/SimuCityDB_en_clean.db'
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
            select: "SELECT household_structure_es, share_within_size FROM vw_household_structure_share_by_size WHERE municipality_code = ? AND household_size_es = ? ORDER BY household_structure_es",
            values: [municipalityCode, normalizedSize]
        ));
        map<string, float> totalsByStructure <- map<string, float>(map([]));
        float totalForSize <- 0.0;
        loop ls over: list<list>(results[2]) {
            string structure <- ls[0] as string;
            string structureLower <- lower_case(structure);
            if (!(structureLower contains "total")) {
                float probability <- (ls[1] = nil) ? 0.0 : max(0.0, ls[1] as float);
                float current <- (totalsByStructure[structure] = nil) ? 0.0 : totalsByStructure[structure];
                totalsByStructure[structure] <- current + probability;
                totalForSize <- totalForSize + probability;
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
            select: "WITH src AS (SELECT mother_age_range, total_births FROM mother_age_distribution WHERE autonomous_community_full = ? AND mother_age_range IS NOT NULL AND mother_age_range <> '') SELECT mother_age_range, ROUND(total_births * 1.0 / NULLIF(SUM(total_births) OVER (), 0), 6) AS probability FROM src;", 
            values: [autonomousCommunity]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- (ls[1] = nil) ? 0.0 : (ls[1] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector; 
    }

    // Read gender distribution probabilities for a given province
    action readSexProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH src AS (SELECT sex_en_key, total_people FROM sex_distribution_by_province WHERE province_full = ? AND sex_en_key IN ('male', 'female')) SELECT sex_en_key, ROUND(total_people * 1.0 / NULLIF(SUM(total_people) OVER (), 0), 6) AS probability FROM src;", 
            values: [province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- (ls[1] = nil) ? 0.0 : (ls[1] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector; 
    }

    // Read partner orientation probabilities for a given province
    action readOrientationProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT couple_type_en_key, SUM(total_couples) AS total_couples FROM couple_type_counts_by_province WHERE province_full = ? AND couple_type_en_key IN ('opposite_sex_couple', 'same_sex_female_couple', 'same_sex_male_couple') GROUP BY couple_type_en_key;", 
            values: [province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([
            "heterosexual" :: 0.0,
            "homosexual" :: 0.0
        ]));
        float totalCouples <- 0.0;
        loop ls over: list<list>(results[2]) {
            string category <- (ls[0] = nil) ? "" : lower_case(ls[0] as string);
            float count <- (ls[1] = nil) ? 0.0 : max(0.0, ls[1] as float);
            if (count > 0.0) {
                if (category = "opposite_sex_couple") {
                    probabilityVector["heterosexual"] <- probabilityVector["heterosexual"] + count;
                } else if (category = "same_sex_female_couple" or category = "same_sex_male_couple") {
                    probabilityVector["homosexual"] <- probabilityVector["homosexual"] + count;
                }
                totalCouples <- totalCouples + count;
            }
        }
        if (totalCouples <= 0.0) {
            return map<string, float>(map([]));
        }
        loop k over: keys(probabilityVector) {
            probabilityVector[k] <- probabilityVector[k] / totalCouples;
        }
        return probabilityVector; 
    }

    // Read absolute couple age-gap probabilities for a given province
    action readCoupleAgeGapProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS,
            select: "SELECT spouse_male_age_range, spouse_female_age_range, SUM(total_couples) AS couples FROM couple_age_gap_counts WHERE province_full = ? AND spouse_male_age_range IS NOT NULL AND spouse_female_age_range IS NOT NULL GROUP BY spouse_male_age_range, spouse_female_age_range;",
            values: [province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([
            "0-4" :: 0.0,
            "5-9" :: 0.0,
            "10-14" :: 0.0,
            "15+" :: 0.0
        ]));
        float totalCouples <- 0.0;
        loop ls over: list<list>(results[2]) {
            string maleRange <- (ls[0] = nil) ? "" : (ls[0] as string);
            string femaleRange <- (ls[1] = nil) ? "" : (ls[1] as string);
            float couples <- (ls[2] = nil) ? 0.0 : max(0.0, ls[2] as float);
            if (couples > 0.0) {
                float maleMid <- 0.0;
                float femaleMid <- 0.0;
                if (maleRange contains "-") {
                    list<string> maleParts <- split_with(maleRange, "-");
                    if (length(maleParts) >= 2) {
                        int maleLo <- maleParts[0] as_int 10;
                        int maleHi <- maleParts[1] as_int 10;
                        maleMid <- (maleLo + maleHi) / 2.0;
                    }
                }
                if (femaleRange contains "-") {
                    list<string> femaleParts <- split_with(femaleRange, "-");
                    if (length(femaleParts) >= 2) {
                        int femaleLo <- femaleParts[0] as_int 10;
                        int femaleHi <- femaleParts[1] as_int 10;
                        femaleMid <- (femaleLo + femaleHi) / 2.0;
                    }
                }
                float gap <- abs(maleMid - femaleMid);
                string bucket <- "15+";
                if (gap < 5.0) { bucket <- "0-4"; }
                else if (gap < 10.0) { bucket <- "5-9"; }
                else if (gap < 15.0) { bucket <- "10-14"; }
                float current <- (probabilityVector[bucket] = nil) ? 0.0 : probabilityVector[bucket];
                probabilityVector[bucket] <- current + couples;
                totalCouples <- totalCouples + couples;
            }
        }
        if (totalCouples <= 0.0) {
            return map<string, float>(map([]));
        }
        loop bucket over: keys(probabilityVector) {
            probabilityVector[bucket] <- probabilityVector[bucket] / totalCouples;
        }
        return probabilityVector;
    }

    // Read age group distribution probabilities for a given province
    action readAgeGroupProbabilities(string province) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalPorGrupo AS (SELECT age_group_range AS GrupoEdad, SUM(total_people) AS TotalGrupo FROM age_group_distribution WHERE sex_en_key = 'both_sexes' AND province_full = ? GROUP BY age_group_range), TotalProvincia AS (SELECT SUM(total_people) AS TotalProvincia FROM age_group_distribution WHERE sex_en_key = 'both_sexes' AND province_full = ?) SELECT GrupoEdad, ROUND(CAST(TotalGrupo AS FLOAT) / NULLIF(TotalProvincia.TotalProvincia, 0), 6) AS Porcentaje FROM TotalPorGrupo, TotalProvincia;", 
            values: [province, province]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- (ls[1] = nil) ? 0.0 : (ls[1] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector; 
    }

    // Read entry or exit probabilities for Leganes based on type ("entry" or "exit")
    action readLeganesEntryExitProbabilities(string type) {
        string municipalityCode <- (statisticsCity = nil or statisticsCity = "") ? "28074" : split_with(statisticsCity, " ")[0];
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT counterpart_municipality_name, CASE WHEN ? = 'entry' THEN entry_probability WHEN ? = 'exit' THEN exit_probability ELSE NULL END AS probability FROM commute_flow_probabilities WHERE source_municipality_code = ?;", 
            values: [type, type, municipalityCode]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- (ls[1] = nil) ? 0.0 : (ls[1] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector;
    }

    // Read district distribution probabilities for Leganes
    action readDistrictProbabilities {
        string municipalityCode <- (statisticsCity = nil or statisticsCity = "") ? "28074" : split_with(statisticsCity, " ")[0];
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "SELECT district_name, total_share FROM district_population_distribution WHERE municipality_code = ? AND is_total_row = 0 ORDER BY district_name;", 
            values: [municipalityCode]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[0] as string;
            float value <- (ls[1] = nil) ? 0.0 : (ls[1] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector;
    }

    // Read transport mode target probabilities (short/long) for a municipality with global fallback
    action readTransportModeProbabilities(string municipality) {
        string municipalityCode <- (municipality = nil or municipality = "") ? "28074" : split_with(municipality, " ")[0];
        list<list> results <- list<list>(select(
            params: PARAMS,
            select: "SELECT distance_class, transport_mode, target_share FROM transport_mode_targets WHERE municipality_code = ?",
            values: [municipalityCode]
        ));
        if (empty(list<list>(results[2]))) {
            results <- list<list>(select(
                params: PARAMS,
                select: "SELECT distance_class, transport_mode, target_share FROM transport_mode_targets WHERE COALESCE(municipality_code, '') = ?",
                values: [""]
            ));
        }

        map<string, float> output <- map<string, float>(map([
            "short_walking" :: walkShortDistanceProbability,
            "short_car" :: carShortDistanceProbability,
            "short_taxi" :: taxiShortDistanceProbability,
            "long_car" :: carLongDistanceProbability,
            "long_train" :: trainLongDistanceProbability,
            "long_taxi" :: taxiLongDistanceProbability
        ]));

        map<string, float> shortRaw <- map<string, float>(map([
            "walking" :: 0.0,
            "car" :: 0.0,
            "taxi" :: 0.0
        ]));
        map<string, float> longRaw <- map<string, float>(map([
            "car" :: 0.0,
            "train" :: 0.0,
            "taxi" :: 0.0
        ]));

        loop ls over: list<list>(results[2]) {
            string distanceClass <- (ls[0] = nil) ? "" : lower_case(ls[0] as string);
            string mode <- (ls[1] = nil) ? "" : lower_case(ls[1] as string);
            float share <- (ls[2] = nil) ? 0.0 : max(0.0, ls[2] as float);
            if (share <= 0.0) { continue; }

            if (distanceClass = "short") {
                if (mode = "walking" or mode = "walk") {
                    shortRaw["walking"] <- shortRaw["walking"] + share;
                } else if (mode = "car") {
                    shortRaw["car"] <- shortRaw["car"] + share;
                } else if (mode = "taxi") {
                    shortRaw["taxi"] <- shortRaw["taxi"] + share;
                }
            } else if (distanceClass = "long") {
                if (mode = "car") {
                    longRaw["car"] <- longRaw["car"] + share;
                } else if (mode = "train") {
                    longRaw["train"] <- longRaw["train"] + share;
                } else if (mode = "taxi") {
                    longRaw["taxi"] <- longRaw["taxi"] + share;
                }
            }
        }

        float shortSum <- shortRaw["walking"] + shortRaw["car"] + shortRaw["taxi"];
        if (shortSum > 0.0) {
            output["short_walking"] <- shortRaw["walking"] / shortSum;
            output["short_car"] <- shortRaw["car"] / shortSum;
            output["short_taxi"] <- shortRaw["taxi"] / shortSum;
        }

        float longSum <- longRaw["car"] + longRaw["train"] + longRaw["taxi"];
        if (longSum > 0.0) {
            output["long_car"] <- longRaw["car"] / longSum;
            output["long_train"] <- longRaw["train"] / longSum;
            output["long_taxi"] <- longRaw["taxi"] / longSum;
        }

        return output;
    }

    // Read husband age coupling probabilities for a given province and wife age
    action readHusbandAgeCoupleProbabilities(string province, string age) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalPorEdad AS (SELECT spouse_male_age_range, spouse_female_age_range, total_couples FROM couple_age_gap_counts WHERE province_full = ? AND spouse_male_age_range = ?), SumaTotal AS (SELECT SUM(total_couples) AS SumaTotalEsposas FROM TotalPorEdad) SELECT t.spouse_male_age_range, t.spouse_female_age_range, t.total_couples, ROUND(t.total_couples * 1.0 / NULLIF(s.SumaTotalEsposas, 0), 6) AS Probabilidad FROM TotalPorEdad t JOIN SumaTotal s ON 1=1 ORDER BY t.spouse_female_age_range;", 
            values: [province, age]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[1] as string; // use wife's age as the key
            float value <- (ls[3] = nil) ? 0.0 : (ls[3] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector; 
    }

    // Read wife age coupling probabilities for a given province and husband age
    action readWifeAgeCoupleProbabilities(string province, string age) {
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH TotalPorEdad AS (SELECT spouse_female_age_range, spouse_male_age_range, total_couples FROM couple_age_gap_counts WHERE province_full = ? AND spouse_female_age_range = ?), SumaTotal AS (SELECT SUM(total_couples) AS SumaTotalEsposos FROM TotalPorEdad) SELECT t.spouse_female_age_range, t.spouse_male_age_range, t.total_couples, ROUND(t.total_couples * 1.0 / NULLIF(s.SumaTotalEsposos, 0), 6) AS Probabilidad FROM TotalPorEdad t JOIN SumaTotal s ON 1=1 ORDER BY t.spouse_male_age_range;", 
            values: [province, age]
        ));
        map<string, float> probabilityVector <- map<string, float>(map([]));
        loop ls over: list<list>(results[2]) {
            string key <- ls[1] as string; // use husband's age as the key
            float value <- (ls[3] = nil) ? 0.0 : (ls[3] as float);
            add value at: key to: probabilityVector;
        }
        return probabilityVector; 
    }

    // Read a random sample of vehicle data based on a percentage of the population
    action readVehicleProbabilities(float percentage) {
        int num_to_select <- max(1, round(percentage * numPeople));
        list<list> results <- list<list>(select(
            params: PARAMS, 
            select: "WITH VehiculosFiltrados AS (SELECT brand, subbrand, version, fuel_type, co2_g_km FROM vehicle_catalog WHERE UPPER(COALESCE(category, '')) != 'AUTOS DE LUJO') SELECT brand, subbrand, version, fuel_type, co2_g_km FROM VehiculosFiltrados ORDER BY RANDOM() LIMIT ?;", 
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
            select: "SELECT household_size_es, households_count, share_within_municipality FROM vw_household_size_share WHERE municipality_code = ? ORDER BY CASE household_size_es WHEN '1 persona' THEN 1 WHEN '2 personas' THEN 2 WHEN '3 personas' THEN 3 WHEN '4 personas' THEN 4 ELSE 5 END",
            values: [municipalityCode]
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
                float count <- (row[1] = nil) ? 0.0 : max(0.0, row[1] as float);
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
        if (motherAgeProbabilities = nil or empty(keys(motherAgeProbabilities))) {
            motherAgeProbabilities <- map<string, float>(map([
                "15-19" :: 0.05,
                "20-24" :: 0.15,
                "25-29" :: 0.30,
                "30-34" :: 0.25,
                "35-39" :: 0.15,
                "40-44" :: 0.07,
                "45-49" :: 0.02,
                "50-59" :: 0.01
            ]));
        }
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
        float orientation_sum <- 0.0;
        if (orientationProbabilities != nil) {
            loop ok over: keys(orientationProbabilities) {
                orientation_sum <- orientation_sum + max(0.0, orientationProbabilities[ok] as float);
            }
        }
        if (orientationProbabilities = nil or empty(keys(orientationProbabilities)) or orientation_sum <= 0.0) {
            orientationProbabilities <- map<string, float>(map(["heterosexual" :: 0.95, "homosexual" :: 0.05]));
        } else {
            loop ok over: keys(orientationProbabilities) {
                orientationProbabilities[ok] <- max(0.0, orientationProbabilities[ok] as float) / orientation_sum;
            }
        }
        coupleAgeGapProbabilities <- readCoupleAgeGapProbabilities(statisticsProvince);
        float couple_gap_sum <- 0.0;
        if (coupleAgeGapProbabilities != nil) {
            loop ck over: keys(coupleAgeGapProbabilities) {
                couple_gap_sum <- couple_gap_sum + max(0.0, coupleAgeGapProbabilities[ck] as float);
            }
        }
        if (coupleAgeGapProbabilities = nil or empty(keys(coupleAgeGapProbabilities)) or couple_gap_sum <= 0.0) {
            coupleAgeGapProbabilities <- map<string, float>(map([
                "0-4" :: 0.58,
                "5-9" :: 0.26,
                "10-14" :: 0.10,
                "15+" :: 0.06
            ]));
        } else {
            loop ck over: keys(coupleAgeGapProbabilities) {
                coupleAgeGapProbabilities[ck] <- max(0.0, coupleAgeGapProbabilities[ck] as float) / couple_gap_sum;
            }
        }
        ageGroupProbabilities                 <- readAgeGroupProbabilities(statisticsProvince);
        loop age over: ["15-19", "20-24", "25-29", "30-34", "35-39", "40-44", "45-49", "50-54", "55-59", "60-99"] {
            husbandAgeCoupleProbabilities[age] <- readHusbandAgeCoupleProbabilities(statisticsProvince, age);
            wifeAgeCoupleProbabilities[age]    <- readWifeAgeCoupleProbabilities(statisticsProvince, age);
            if (husbandAgeCoupleProbabilities[age] = nil or empty(keys(husbandAgeCoupleProbabilities[age]))) {
                husbandAgeCoupleProbabilities[age] <- map<string, float>(map([age :: 1.0]));
            }
            if (wifeAgeCoupleProbabilities[age] = nil or empty(keys(wifeAgeCoupleProbabilities[age]))) {
                wifeAgeCoupleProbabilities[age] <- map<string, float>(map([age :: 1.0]));
            }
        }
        leganesEntryProbabilities             <- readLeganesEntryExitProbabilities("entry");
        leganesExitProbabilities              <- readLeganesEntryExitProbabilities("exit");
        if (leganesEntryProbabilities = nil or empty(keys(leganesEntryProbabilities))) {
            leganesEntryProbabilities <- map<string, float>(map(["Leganes" :: 1.0]));
        }
        if (leganesExitProbabilities = nil or empty(keys(leganesExitProbabilities))) {
            leganesExitProbabilities <- map<string, float>(map(["Leganes" :: 1.0]));
        }
        districtDistributionProbabilities     <- readDistrictProbabilities();
        if (districtDistributionProbabilities = nil or empty(keys(districtDistributionProbabilities))) {
            districtDistributionProbabilities <- map<string, float>(map([
                "Sur" :: 0.165,
                "Norte" :: 0.1164,
                "San Nicasio" :: 0.1638,
                "Zarzaquemada" :: 0.2443,
                "Carrascal" :: 0.1736,
                "Fortuna" :: 0.0678,
                "Polvoranca" :: 0.0691
            ]));
        }
        map<string, float> transportModeProbabilities <- readTransportModeProbabilities(statisticsCity);
        walkShortDistanceProbability <- (transportModeProbabilities["short_walking"] = nil) ? walkShortDistanceProbability : transportModeProbabilities["short_walking"];
        carShortDistanceProbability <- (transportModeProbabilities["short_car"] = nil) ? carShortDistanceProbability : transportModeProbabilities["short_car"];
        taxiShortDistanceProbability <- (transportModeProbabilities["short_taxi"] = nil) ? taxiShortDistanceProbability : transportModeProbabilities["short_taxi"];
        carLongDistanceProbability <- (transportModeProbabilities["long_car"] = nil) ? carLongDistanceProbability : transportModeProbabilities["long_car"];
        trainLongDistanceProbability <- (transportModeProbabilities["long_train"] = nil) ? trainLongDistanceProbability : transportModeProbabilities["long_train"];
        taxiLongDistanceProbability <- (transportModeProbabilities["long_taxi"] = nil) ? taxiLongDistanceProbability : transportModeProbabilities["long_taxi"];
        vehicleConsumptionMatrix              <- readVehicleProbabilities(0.4);
        if (vehicleConsumptionMatrix = nil or empty(vehicleConsumptionMatrix)) {
            vehicleConsumptionMatrix <- [
                map<string, string>(
                    "Brand" :: "unknown",
                    "Subbrand" :: "",
                    "Version" :: "",
                    "Fuel" :: "unknown",
                    "CO2_g_km" :: "0"
                )
            ];
        }
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
    reflex breakdown when: enableBreakdowns and !breakdown and flip(probabilityBreakdown) {
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
    
    // Stop durations for different control types
    float timeToStopInAStop <- 5.0;
    float timeToStopInAZebraCrossing <- 5.0;
    float contStop <- 0.0;
    
    // Breakdown and Stuck recovery variables
    float breakdown_timer <- 0.0;
    float breakdown_duration <- broken_removal_minutes; // Removal delay once broken
    float stuck_removal_duration <- 5.0 #mn;  // Remove vehicle if fully stopped for too long
    
    
    // References to route intersections
    crossroads initialCrossroad;
    crossroads targetCrossroads;
    
    // Congestion tracking variables
    float thresholdStucked <- 1.0 #mn;         // Default threshold for attempting escape
    float counterStucked <- 0.0;
    bool stuck_state_active <- false;
    int stuck_progress_bucket <- 0;
    float stuck_state_start_time <- -1.0;
    
    // Detection distances (from globals)
    float closeDistance <- closeDistance;
    float farDistance <- farDistance;
    
    // Route control state
    // Passenger list
    list<Person> passengers <- [];
    
    // Yield/stop blocking state
    bool isBlocked;
    
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

    // Yield signs are encoded at node level in CROSSROADS, but right-of-way is approach-specific.
    // A vehicle should yield only if the approach it comes from has a give_way marker.
    bool is_yield_approach_for_node(crossroads node) {
        if (node = nil or current_road = nil) { return false; }
        roads curRoad <- roads(current_road);
        crossroads upstream <- using_linked_road ? crossroads(curRoad.target_node) : crossroads(curRoad.source_node);
        crossroads downstream <- using_linked_road ? crossroads(curRoad.source_node) : crossroads(curRoad.target_node);
        if (downstream = nil or downstream != node) { return false; }
        return (upstream != nil and upstream.isYield);
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

    action log_route_plan_event(string agent_kind, string mode_label, string result_label, int attempts) {
        if (simLogger != nil) {
            int safe_attempts <- max(1, attempts);
            string details <- "agent:" + agent_kind + "|mode:" + mode_label + "|result:" + result_label + "|attempts:" + safe_attempts;
            ask simLogger {
                do log_event("ROUTE_PLAN," + time + "," + myself.name + "," + mode_label + "," + details + ",0,0");
            }
        }
    }

    // Local helper so vehicle species can refresh taxi registry without relying on global action scope
    action refresh_taxi_registry {
        if (taxiCallCenter != nil) {
            list<electricCars> alive_taxis <- electricCars where (each != nil and !dead(each));
            taxiCallCenter.registeredTaxis <- alive_taxis;
            taxiCallCenter.freeTaxis <- length(alive_taxis where (each.lowBattery = false and each.isAvailable and each.isWandering));
        }
    }

    action clear_stuck_tracking(string agent_kind, string mode_label, string reason_label) {
        bool was_stuck <- stuck_state_active or counterStucked > 0.0;
        if (was_stuck and simLogger != nil) {
            string details <- "agent:" + agent_kind + "|mode:" + mode_label + "|state:clear|reason:" + reason_label
                + "|stuck_minutes:" + (counterStucked / #mn)
                + "|stuck_start_time:" + stuck_state_start_time;
            ask simLogger {
                do log_event("ROUTE_STUCK_STATE," + time + "," + myself.name + "," + mode_label + "," + details + ",0,0");
            }
        }
        counterStucked <- 0.0;
        stuck_state_active <- false;
        stuck_progress_bucket <- 0;
        stuck_state_start_time <- -1.0;
    }

    action update_stuck_tracking(string agent_kind, string mode_label, string phase_label) {
        if (speed < 0.01 #km / #h) {
            counterStucked <- counterStucked + step;
            if (!stuck_state_active) {
                stuck_state_active <- true;
                stuck_state_start_time <- time;
                stuck_progress_bucket <- 0;
                if (simLogger != nil) {
                    string details_start <- "agent:" + agent_kind + "|mode:" + mode_label + "|phase:" + phase_label
                        + "|state:start|speed_kmh:" + (speed / (#km / #h))
                        + "|stuck_minutes:" + (counterStucked / #mn)
                        + "|threshold_minutes:" + (stuck_removal_duration / #mn);
                    ask simLogger {
                        do log_event("ROUTE_STUCK_STATE," + time + "," + myself.name + "," + mode_label + "," + details_start + ",0,0");
                    }
                }
            }

            int current_bucket <- int(counterStucked / (1.0 #mn));
            if (current_bucket > stuck_progress_bucket) {
                stuck_progress_bucket <- current_bucket;
                if (simLogger != nil) {
                    string details_progress <- "agent:" + agent_kind + "|mode:" + mode_label + "|phase:" + phase_label
                        + "|state:progress|bucket_min:" + current_bucket
                        + "|stuck_minutes:" + (counterStucked / #mn)
                        + "|threshold_minutes:" + (stuck_removal_duration / #mn);
                    ask simLogger {
                        do log_event("ROUTE_STUCK_STATE," + time + "," + myself.name + "," + mode_label + "," + details_progress + ",0,0");
                    }
                }
            }
        } else {
            do clear_stuck_tracking(agent_kind, mode_label, "movement_resumed");
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
            if (!nextCrossroad.isYield) {
                nextIsYield <- false;
                carInAYield <- false;
                carStopInAYield <- false;
            }
            if (!nextCrossroad.isStop) { nextIsStop <- false; carStopInAStop <- false; }
            if (!nextCrossroad.isZebraCrossing) { nextIsZebra <- false; carStopInAZebraCrossing <- false; }

            // 2. Yield Logic
            if (nextCrossroad.isYield) {
                bool applyYield <- is_yield_approach_for_node(nextCrossroad);
                if (!applyYield) {
                    nextIsYield <- false;
                    carInAYield <- false;
                    carStopInAYield <- false;
                } else if (!nextIsYield and dist <= triggerDist) {
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
            string stuck_agent <- (self is electricCars) ? "taxi" : "car";
            string stuck_mode <- (self is electricCars) ? "taxi" : "car";
            do clear_stuck_tracking(stuck_agent, stuck_mode, "zebra_released");
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Pause at yield signs if cross traffic is present
    /////////////////////////////////////////////////////////////
    reflex stopToYield when: current_path != nil and final_target != nil and carStopInAZebraCrossing = false and carStopInAStop = false and carInAYield = true {
        isBlocked <- false;
        crossroads nextCrossroad <- crossroads(current_target);
        bool myApproachYield <- is_yield_approach_for_node(nextCrossroad);
        if (!myApproachYield) {
            // Safety reset: if a non-yield approach was incorrectly latched, release immediately.
            nextCrossroad.stop <- [];
            carStopInAYield <- false;
            carInAYield <- false;
            nextIsYield <- false;
            string stuck_agent <- (self is electricCars) ? "taxi" : "car";
            string stuck_mode <- (self is electricCars) ? "taxi" : "car";
            do clear_stuck_tracking(stuck_agent, stuck_mode, "yield_not_applicable");
        } else {
        loop k over: nextCrossroad.roads_in {
            if (roads(k) != current_road) {
                roads incomingRoad <- roads(k);
                crossroads incomingSrc <- crossroads(incomingRoad.source_node);
                bool incomingIsYieldApproach <- (incomingSrc != nil and incomingSrc.isYield);
                // Only priority (non-yield) incoming streams should block a yielding approach.
                if (incomingIsYieldApproach) { continue; }
                list<vehicles> incomingVehicles <- list<vehicles>(incomingRoad.all_agents);
                // Block only if there are conflicting vehicles with effective movement intent near the node.
                if (!empty(incomingVehicles where (
                    !dead(each)
                    and each != self
                    and (each.location distance_to nextCrossroad.location < 15.0 #meters)
                    and (
                        each.speed > 0.5 #km / #h
                        or (
                            each.carStopInAStop = false
                            and each.carStopInAZebraCrossing = false
                            and each.carStopInAYield = false
                        )
                    )
                ))) {
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
            carInAYield <- false;
            nextIsYield <- false;
            string stuck_agent <- (self is electricCars) ? "taxi" : "car";
            string stuck_mode <- (self is electricCars) ? "taxi" : "car";
            do clear_stuck_tracking(stuck_agent, stuck_mode, "yield_released");
        }
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
            string stuck_agent <- (self is electricCars) ? "taxi" : "car";
            string stuck_mode <- (self is electricCars) ? "taxi" : "car";
            do clear_stuck_tracking(stuck_agent, stuck_mode, "stop_released");
        }
    }
    
    /////////////////////////////////////////////////////////////
    // Reflex: Simulate vehicle breakdown
    // When a car breaks down, its speed is set to 0.0 to stop movement.
    /////////////////////////////////////////////////////////////
    reflex breakdown when: enableBreakdowns and !breakdown and flip(probabilityBreakdown) {
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
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                } else if (p.living_place != nil) {
                    p.location <- p.living_place.location;
                }
                p.the_target <- nil;
                p.isMoving <- false;
                p.stopped <- true;
                ask p { do end_trip_log("ABORTED_" + (myself.breakdown ? "BREAKDOWN" : "STUCK")); }
                write "Recovery: Passenger " + p + " relocated to destination/home fallback due to " + reason + ".";
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
    int routePlanAttempts <- 0;
    bool routePlanOutcomeLogged <- false;
    int routePlanFailureThreshold <- 60;
    crossroads planned_car_origin <- nil;
    crossroads planned_car_destination <- nil;
    crossroads nextNode;
    // CO2 consumption tracking
    string carModel;
    string fuel;
    float CO2_g_km;
    float consumoCO2 <- 0.0;
    
    // Reflex: Plan route when idle
    reflex timeToGoNormalCars when: final_target = nil and carStopInAZebraCrossing = false and carStopInAStop = false {
        crossroads route_source <- initialCrossroad;
        if (location != nil) {
            crossroads closest_source <- (crossroads where !(each.crossroadsNoInitialLocation) closest_to self.location);
            if (closest_source != nil) { route_source <- closest_source; }
        }
        crossroads failed_route_origin <- route_source;
        crossroads failed_route_destination <- targetCrossroads;
        if (targetCrossroads = nil) {
            targetCrossroads <- (crossroads where !(each.crossroadsNoInitialLocation) closest_to self.location);
            failed_route_destination <- targetCrossroads;
        }
        routePlanAttempts <- routePlanAttempts + 1;
        planned_car_origin <- route_source;
        planned_car_destination <- targetCrossroads;
        if (route_source != nil and targetCrossroads != nil and route_source = targetCrossroads) {
            if (!routePlanOutcomeLogged) {
                do log_route_plan_event("car", "car", "first_try_success", routePlanAttempts);
                routePlanOutcomeLogged <- true;
            }
            loop p over: passengers {
                if (p != nil) {
                    if (p.the_target != nil) {
                        p.location <- p.the_target.location;
                    }
                    if (p.current_trip_id != nil) {
                        ask p { do end_trip_log("COMPLETED"); }
                    }
                    p.the_target <- nil;
                    p.isMoving <- false;
                    p.startJourney <- false;
                    p.stopped <- true;
                    p.newObjective <- false;
                    p.forcedWalkMode <- false;
                    p.assigned_vehicle <- nil;
                }
            }
            do die;
        }
        if (route_source != nil) {
            location <- route_source.location;
            initialCrossroad <- route_source;
        }
        current_path <- nil;
        final_target <- nil;
        bool planner_path_found <- false;
        bool final_target_ready <- false;
        bool planner_state_ready <- false;
        int recovery_trigger <- int(min(10, max(3, routePlanFailureThreshold - 1)));
        if (route_source != nil and targetCrossroads != nil) {
            current_path <- compute_path(graph: roadsNetwork, target: targetCrossroads);
            planner_path_found <- (current_path != nil);
            if (!planner_path_found) {
                numTimesCurrentPathNull <- numTimesCurrentPathNull + 1;
                if (numTimesCurrentPathNull >= recovery_trigger) {
                    float search_radius <- initialSearchRadius;
                    list<crossroads> potentialLocations <- crossroads where (
                        distance_to(each.location, self.location) < search_radius and !(each.crossroadsNoInitialLocation)
                    ) sort_by (distance_to(each.location, self.location));
                    list<crossroads> potentialTargets <- crossroads where (
                        distance_to(each.location, targetCrossroads.location) < search_radius and !(each.crossroadsNoInitialLocation)
                    ) sort_by (distance_to(each.location, targetCrossroads.location));
                    if (empty(potentialLocations) and route_source != nil) { potentialLocations <- [route_source]; }
                    if (empty(potentialTargets) and targetCrossroads != nil) { potentialTargets <- [targetCrossroads]; }
                    loop initialCrossroadSwitch over: potentialLocations {
                        if (current_path != nil or routePlanAttempts >= routePlanFailureThreshold) { break; }
                        loop targetCrossroadSwitch over: potentialTargets {
                            if (current_path != nil or routePlanAttempts >= routePlanFailureThreshold) { break; }
                            bool valid_pair <- (initialCrossroadSwitch != nil and targetCrossroadSwitch != nil);
                            bool duplicate_direct <- (initialCrossroadSwitch = route_source and targetCrossroadSwitch = targetCrossroads);
                            if (valid_pair and !duplicate_direct) {
                                failed_route_origin <- initialCrossroadSwitch;
                                failed_route_destination <- targetCrossroadSwitch;
                                planned_car_origin <- initialCrossroadSwitch;
                                planned_car_destination <- targetCrossroadSwitch;
                                routePlanAttempts <- routePlanAttempts + 1;
                                location <- initialCrossroadSwitch.location;
                                initialCrossroad <- initialCrossroadSwitch;
                                current_path <- compute_path(graph: roadsNetwork, target: targetCrossroadSwitch);
                                if (current_path != nil) {
                                    targetCrossroads <- targetCrossroadSwitch;
                                    break;
                                }
                            }
                        }
                    }
                }
            } else {
                numTimesCurrentPathNull <- 0;
            }
        }
        planner_path_found <- (current_path != nil);
        if (planner_path_found and !final_target_ready and targetCrossroads != nil) {
            final_target <- targetCrossroads;
            final_target_ready <- (final_target != nil);
        } else {
            final_target_ready <- (final_target != nil);
        }
        final_target_ready <- (final_target != nil);
        planner_state_ready <- (planner_path_found and final_target_ready);
        if (planner_state_ready) {
            numTimesCurrentPathNull <- 0;
            initialCrossroad <- planned_car_origin;
        }

        if (planner_state_ready and !routePlanOutcomeLogged) {
            string route_result <- (routePlanAttempts = 1) ? "first_try_success" : "recovered_after_retries";
            do log_route_plan_event("car", "car", route_result, routePlanAttempts);
            routePlanOutcomeLogged <- true;
        }

        if (!planner_state_ready and routePlanAttempts >= routePlanFailureThreshold) {
            if (!routePlanOutcomeLogged) {
                do log_route_plan_event("car", "car", "failed_after_retries", routePlanAttempts);
                routePlanOutcomeLogged <- true;
            }
            if (simLogger != nil) {
                string failed_vehicle_id <- name;
                int failed_attempts <- max(1, routePlanAttempts);
                loop p over: passengers {
                    if (p != nil) {
                        string failed_person_id <- (p.name = nil) ? string(p) : p.name;
                        string failed_trip_id <- (p.current_trip_id = nil) ? "" : p.current_trip_id;
                        ask simLogger {
                            do log_failed_car_trip_crossroads(
                                failed_person_id,
                                failed_trip_id,
                                failed_vehicle_id,
                                "failed_after_retries",
                                failed_attempts,
                                failed_route_origin,
                                failed_route_destination
                            );
                        }
                    }
                }
            }
            loop p over: passengers {
                if (p != nil) {
                    p.location <- self.location;
                    if (p.current_trip_id != nil) {
                        ask p { do end_trip_log("ABORTED_NO_ROUTE_CAR"); }
                    }
                    p.the_target <- nil;
                    p.isMoving <- false;
                    p.startJourney <- false;
                    p.stopped <- true;
                    p.newObjective <- false;
                    p.forcedWalkMode <- false;
                    p.assigned_vehicle <- nil;
                }
            }
            do die;
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
            do update_stuck_tracking("car", "car", "driving");
            int stepsThreshold <- max(1, int(thresholdStucked / step));
            int stuckSteps <- int(counterStucked / step);
            if (stuckSteps > 0 and (stuckSteps mod stepsThreshold = 0)) {
                proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.2]);
            } else if (counterStucked <= 0.0) {
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
            do clear_stuck_tracking("car", "car", "trip_completed");
            do die;
        }
    }

    // Remove car if it remains stopped for too long while on-route
    reflex removeStuckNormalCar when: !breakdown
        and current_path != nil
        and final_target != nil
        and carStopInAStop = false
        and carStopInAZebraCrossing = false
        and carStopInAYield = false
        and counterStucked >= stuck_removal_duration {
        if (simLogger != nil) {
            string stuck_details <- "agent:car|mode:car|stuck_minutes:" + (counterStucked / #mn)
                + "|threshold_minutes:" + (stuck_removal_duration / #mn)
                + "|stuck_start_time:" + stuck_state_start_time;
            ask simLogger {
                do log_event("ROUTE_STUCK_REMOVAL," + time + "," + myself.name + ",car," + stuck_details + ",0,0");
            }
        }
        loop p over: passengers {
            if (p != nil) {
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                } else if (p.living_place != nil) {
                    p.location <- p.living_place.location;
                }
                if (p.current_trip_id != nil) { ask p { do end_trip_log("ABORTED_STUCK_CAR"); } }
                p.the_target <- nil;
                p.isMoving <- false;
                p.startJourney <- false;
                p.stopped <- true;
                p.newObjective <- false;
                p.forcedWalkMode <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengers <- [];
        do clear_stuck_tracking("car", "car", "removed_stuck_threshold");
        do die;
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

    bool carStopInAElectricRecharge <- false;               // Flag for pausing at charging station
    bool lowBattery <- false;                               // Indicates low battery state
    float timeToStopInAElectricRecharge;                    // Duration to recharge at station

    // Battery state and connector
    float soc;                                              // State of Charge (0.0 to 1.0)
    string typeConnector;                                   // Connector type (e.g., CCS2, Type2, ChaDeMo)
    float capacityCnom <- 28.0;                             // Nominal battery capacity in kWh
    float tension <- 360.0;                                 // Battery voltage in V
    float efficiency <- 11.5 / 100.0;                       // Energy consumption per km (kWh/km)

    // Current trip info
    Trip currentTrip <- nil;                                // Active trip details

    // Route and charging variables
    crossroads closestChargingPoint;                        // Nearest compatible charging station

    int numTimesCurrentPathNull <- 0;                       // Counter for pathfinding failures

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
        currentTrip.tripCost <- currentTrip.tripTime * 0.05;                       // Calculate fare at EUR 0.05 per unit time
    }

    action adopt_pending_taxi_request {
        if (rideRequest and !headingToPickUpPassenger and !headingToDropOffPassenger) {
            headingToPickUpPassenger <- true;
            isAvailable <- false;
            isWandering <- false;
            rideRequest <- false;
            do refresh_taxi_registry;
            if (simLogger != nil) {
                ask simLogger {
                    do log_event("TAXI_REQUEST_ADOPTED," + time + "," + myself.name + ",taxi,pickup_phase_started,0,0");
                }
            }
        }
    }

    action set_taxi_phase_target {
        if (headingToPickUpPassenger and !empty(passengersToPickUp)) {
            Person p_pick <- first(passengersToPickUp where (each != nil));
            if (p_pick != nil) {
                targetCrossroads <- (crossroads where !each.crossroadsNoInitialLocation) closest_to p_pick.location;
            }
        } else if (headingToDropOffPassenger and !empty(passengers)) {
            Person p_drop <- first(passengers where (each != nil and each.the_target != nil));
            if (p_drop != nil and p_drop.the_target != nil) {
                targetCrossroads <- (crossroads where !each.crossroadsNoInitialLocation) closest_to p_drop.the_target.location;
            }
        } else if (targetCrossroads = nil) {
            targetCrossroads <- one_of(crossroads where !each.crossroadsNoInitialLocation);
        }
    }

    action fallback_complete_trip_and_release_taxi(string reason_label) {
        if (simLogger != nil) {
            ask simLogger {
                do log_event("TAXI_FALLBACK_COMPLETE," + time + "," + myself.name + ",taxi," + reason_label + ",0,0");
            }
        }

        loop p over: passengers {
            if (p != nil) {
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                } else if (p.living_place != nil) {
                    p.location <- p.living_place.location;
                }
                if (p.current_trip_id != nil) { ask p { do end_trip_log("COMPLETED"); } }
                p.the_target <- nil;
                p.stopped <- true;
                p.isMoving <- false;
                p.startJourney <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengers <- [];

        loop p over: passengersToPickUp {
            if (p != nil) {
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                } else if (p.living_place != nil) {
                    p.location <- p.living_place.location;
                }
                if (p.current_trip_id != nil) { ask p { do end_trip_log("COMPLETED"); } }
                p.the_target <- nil;
                p.stopped <- true;
                p.isMoving <- false;
                p.startJourney <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengersToPickUp <- [];

        headingToPickUpPassenger <- false;
        headingToDropOffPassenger <- false;
        rideRequest <- false;
        isAvailable <- true;
        isWandering <- true;
        final_target <- nil;
        current_path <- nil;
        targetCrossroads <- one_of(crossroads where !each.crossroadsNoInitialLocation);
        numTimesCurrentPathNull <- 0;

        if (currentTrip != nil) {
            if (currentTrip.pickupTime = nil) {
                currentTrip.pickupTime <- current_date;
            }
            currentTrip.completionTime <- current_date;
            currentTrip.tripStatus <- "Completed_fallback";
            if (taxiCallCenter != nil) {
                taxiCallCenter.finishedTrips <- taxiCallCenter.finishedTrips + currentTrip;
            }
            do calculateTaxiFare;
            currentTrip <- nil;
        }

        do refresh_taxi_registry;
    }

    action abort_active_taxi_trip_no_route(string reason_label) {
        if (simLogger != nil) {
            ask simLogger {
                do log_event("TAXI_ROUTE_ABORT," + time + "," + myself.name + ",taxi," + reason_label + ",0,0");
            }
        }

        loop p over: passengers {
            if (p != nil) {
                p.location <- self.location;
                if (p.current_trip_id != nil) { ask p { do end_trip_log("ABORTED_NO_ROUTE_TAXI"); } }
                p.the_target <- nil;
                p.stopped <- true;
                p.isMoving <- false;
                p.startJourney <- false;
                p.newObjective <- false;
                p.forcedWalkMode <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengers <- [];

        loop p over: passengersToPickUp {
            if (p != nil) {
                if (p.current_trip_id != nil) { ask p { do end_trip_log("ABORTED_NO_ROUTE_TAXI_PICKUP"); } }
                p.the_target <- nil;
                p.stopped <- true;
                p.isMoving <- false;
                p.startJourney <- false;
                p.newObjective <- false;
                p.forcedWalkMode <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengersToPickUp <- [];

        headingToPickUpPassenger <- false;
        headingToDropOffPassenger <- false;
        headingToChargingPoint <- false;
        rideRequest <- false;
        isAvailable <- true;
        isWandering <- true;
        final_target <- nil;
        current_path <- nil;
        targetCrossroads <- nil;
        numTimesCurrentPathNull <- 0;

        if (currentTrip != nil) {
            currentTrip.completionTime <- current_date;
            currentTrip.tripStatus <- "Aborted_no_route";
            if (taxiCallCenter != nil) {
                taxiCallCenter.finishedTrips <- taxiCallCenter.finishedTrips + currentTrip;
            }
            currentTrip <- nil;
        }

        do clear_stuck_tracking("taxi", "taxi", "abort_no_route");
        do refresh_taxi_registry;
    }

    action drainBattery {
        // Compute state-of-charge reduction based on distance and efficiency
        float socCalc <- (speed*step*efficiency/1000)/capacityCnom;
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
            do adopt_pending_taxi_request;
            do set_taxi_phase_target;
            crossroads route_source <- (crossroads where !each.crossroadsNoInitialLocation) closest_to self.location;
            if (route_source != nil) { location <- route_source.location; }
            current_path <- (targetCrossroads = nil) ? nil : compute_path(graph: roadsNetwork, target: targetCrossroads);
            if (current_path = nil) {
                numTimesCurrentPathNull <- numTimesCurrentPathNull + 1;
            } else {
                numTimesCurrentPathNull <- 0;
            }

            bool taxi_trip_active <- (currentTrip != nil or headingToPickUpPassenger or headingToDropOffPassenger or rideRequest or !empty(passengersToPickUp) or !empty(passengers));
            if (taxi_trip_active and current_path = nil) {
                do abort_active_taxi_trip_no_route("no_route_direct");
            }
        }
    }

    // Reflex: electric cars with low battery navigate to a charging point
    reflex timeToGoElectricCarsWithoutBattery
    when: lowBattery = true
       and final_target = nil
       and headingToChargingPoint = false
       and carStopInAElectricRecharge = false
       and carStopInAStop = false
       and carStopInAYield = false
       and carStopInAZebraCrossing = false {
       list<crossroads> chargeCandidates <- [];
       if (typeConnector = "CCS2") {
           chargeCandidates <- crossroads where each.hasCCS2;
       } else if (typeConnector = "Type2") {
           chargeCandidates <- crossroads where each.hasType2;
       } else if (typeConnector = "ChaDeMo") {
           chargeCandidates <- crossroads where each.hasChaDeMo;
       } else {
           chargeCandidates <- crossroads where (each.hasCCS2 or each.hasType2 or each.hasChaDeMo);
       }

       chargeCandidates <- chargeCandidates sort_by (distance_to(each.location, self.location));

       int attempts_before <- numTimesCurrentPathNull;
       crossroads selected_charge_candidate <- nil;
       if (!empty(chargeCandidates)) {
           selected_charge_candidate <- first(chargeCandidates);
       }

       closestChargingPoint <- selected_charge_candidate;
       crossroads route_source <- (crossroads where !each.crossroadsNoInitialLocation) closest_to self.location;
       if (route_source != nil) { location <- route_source.location; }
       current_path <- (selected_charge_candidate = nil) ? nil : compute_path(graph: roadsNetwork, target: selected_charge_candidate);
       bool found_route <- (current_path != nil);
       headingToChargingPoint <- found_route;
       if (found_route) {
           final_target <- selected_charge_candidate;
           numTimesCurrentPathNull <- 0;
       } else {
           numTimesCurrentPathNull <- numTimesCurrentPathNull + 1;
           current_path <- nil;
           final_target <- nil;
           headingToChargingPoint <- false;
       }

       if (simLogger != nil) {
           string plan_result <- found_route ? "first_try_success" : "failed_after_retries";
           string details <- "phase:charging|result:" + plan_result
               + "|connector:" + typeConnector
               + "|attempts_before:" + attempts_before
               + "|attempts_after:" + numTimesCurrentPathNull;
           ask simLogger {
               do log_event("TAXI_CHARGING_ROUTE_PLAN," + time + "," + myself.name + ",taxi," + details + ",0,0");
           }
       }

       write "" + self + " -1 from free taxis due to charging.";
       do refresh_taxi_registry;
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
           write "" + self + " +1 to free taxis after charging.";
           do refresh_taxi_registry;
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
           write "" + self + " -1 from free taxis after passenger assignment.";
           do refresh_taxi_registry;
       
       } else {
           // Continue towards destination
           if (final_target != nil) {
                string taxi_phase <- headingToPickUpPassenger ? "pickup"
                    : (headingToDropOffPassenger ? "dropoff" : (headingToChargingPoint ? "charging" : (isWandering ? "wandering" : "driving")));
                do update_stuck_tracking("taxi", "taxi", taxi_phase);
                int stepsThreshold <- max(1, int(thresholdStucked / step));
                int stuckSteps <- int(counterStucked / step);
                if (stuckSteps > 0 and (stuckSteps mod stepsThreshold = 0)) {
                    proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.2]);
                } else if (counterStucked <= 0.0) {
                    proba_use_linked_road <- 0.0;
                }
               do trafficControl;
           
            // Arrived or no path to advance
            } else {
                if (final_target != nil) {
                    write "Vehicle " + self + " has reached destination: " + final_target;
                } else {
                    write "Vehicle " + self + " reached its destination.";
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
                   write "" + self + " +1 to free taxis.";
                   do refresh_taxi_registry;
           
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
               do clear_stuck_tracking("taxi", "taxi", "phase_completed");
           }
       }
    }

    // Remove taxi if it remains stopped for too long while on-route
    reflex removeStuckElectricTaxi when: !breakdown
       and current_path != nil
       and final_target != nil
       and carStopInAStop = false
       and carStopInAYield = false
       and carStopInAZebraCrossing = false
       and counterStucked >= stuck_removal_duration {
        string phase <- headingToPickUpPassenger ? "pickup"
            : (headingToDropOffPassenger ? "dropoff" : (headingToChargingPoint ? "charging" : (isWandering ? "wandering" : "unknown")));
        if (simLogger != nil) {
            string stuck_details <- "agent:taxi|mode:taxi|phase:" + phase
                + "|stuck_minutes:" + (counterStucked / #mn)
                + "|threshold_minutes:" + (stuck_removal_duration / #mn)
                + "|stuck_start_time:" + stuck_state_start_time;
            ask simLogger {
                do log_event("ROUTE_STUCK_REMOVAL," + time + "," + myself.name + ",taxi," + stuck_details + ",0,0");
            }
        }

        loop p over: passengers {
            if (p != nil) {
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                } else if (p.living_place != nil) {
                    p.location <- p.living_place.location;
                }
                if (p.current_trip_id != nil) { ask p { do end_trip_log("ABORTED_STUCK_TAXI"); } }
                p.the_target <- nil;
                p.isMoving <- false;
                p.startJourney <- false;
                p.stopped <- true;
                p.newObjective <- false;
                p.forcedWalkMode <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengers <- [];

        loop p over: passengersToPickUp {
            if (p != nil) {
                if (p.the_target != nil) {
                    p.location <- p.the_target.location;
                } else if (p.living_place != nil) {
                    p.location <- p.living_place.location;
                }
                if (p.current_trip_id != nil) { ask p { do end_trip_log("ABORTED_STUCK_TAXI_PICKUP"); } }
                p.the_target <- nil;
                p.isMoving <- false;
                p.startJourney <- false;
                p.stopped <- true;
                p.newObjective <- false;
                p.forcedWalkMode <- false;
                p.assigned_vehicle <- nil;
            }
        }
        passengersToPickUp <- [];

        if (currentTrip != nil) {
            currentTrip.completionTime <- current_date;
            currentTrip.tripStatus <- "Aborted_stuck";
            if (taxiCallCenter != nil) {
                taxiCallCenter.finishedTrips <- taxiCallCenter.finishedTrips + currentTrip;
            }
            currentTrip <- nil;
        }
        do clear_stuck_tracking("taxi", "taxi", "removed_stuck_threshold");
        do die;
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
    bool startJourney <- false;           // Start trigger for the movement reflex
    bool waitingForTrain <- false;
    crossroads planned_walk_origin <- nil;
    crossroads planned_walk_destination <- nil;
    int walking_route_attempts <- 0;

    // --- Traceability ---
    string current_trip_id <- nil;
    string current_origin_type <- "home";
    point current_origin_geom <- location;
    float current_trip_start_time <- 0.0;
    string current_trip_mode <- nil;
    string current_purpose <- nil;
    int trip_counter <- 0;
    int walk_route_retry_limit <- 40;
    bool walking_route_outcome_logged <- false;

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

    action log_route_plan_event(string result_label, int attempts) {
        if (simLogger != nil) {
            int safe_attempts <- max(1, attempts);
            string details <- "agent:person_walking|mode:walking|result:" + result_label + "|attempts:" + safe_attempts;
            ask simLogger {
                do log_event("ROUTE_PLAN," + time + "," + myself.name + ",walking," + details + ",0,0");
            }
        }
    }
    // --------------------
    // Variables for pedestrian crossings
    crossroads stationAgent;
    string stationString;
    bool isCrossing;                       // True while crossing a zebra crossing
    crossroads nextNode <- nil;
    int positionCurrentEdge <- 0;
    int cycles;
    // Counter for when no route is found in goto
    int nullTTCount <- 0;
    float last_distance_to_finish <- -1.0;
    int walk_no_progress_cycles <- 0;

    // Initialization: assign attributes based on age and determine initial destinations
    init {
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
       
        // If home is not a city type and person is young/adult, update workplace based on Leganes exit probabilities
        if (!(living_place.buildingType = "city") and ((age_group = "Young" and !is_student) or age_group = "Adult")) {
            // Use Leganes exit probabilities
            string leganesExitRaw <- rnd_choice(leganesExitProbabilities);
            string leganesExit <- leganesExitRaw;
            string _exit_norm <- lower_case(leganesExitRaw);
            if (_exit_norm contains "legan") { leganesExit <- "Leganes"; }
            else if (_exit_norm contains "alcor") { leganesExit <- "Alcorcon"; }
            else if (_exit_norm contains "fuenla") { leganesExit <- "Fuenlabrada"; }
            else if (_exit_norm contains "getafe") { leganesExit <- "Getafe norte"; }
            else if (_exit_norm contains "humanes") { leganesExit <- "Extremadura"; }
            else if (_exit_norm contains "madr") { leganesExit <- "Madrid"; }
            else if (_exit_norm contains "mostol" or _exit_norm contains "stol") { leganesExit <- "Mostoles"; }
            if (leganesExit != nil and !(leganesExit = "Leganes")) {
                building externalWork <- first(building where (each.buildingType = "city" and each.buildingName = leganesExit));
                if (externalWork != nil) { working_place <- externalWork; }
            }
        }
		
        // Assign name, objective, and initial location
        name <- "Person_" + (index);
        objective <- "resting";
        if (living_place != nil) { self.location <- living_place.location; }
        if (working_place != nil) {
            string wp_type <- (working_place.buildingType = nil or working_place.buildingType = "") ? "unknown_type" : working_place.buildingType;
            string wp_leisure <- (working_place.leisureType = nil or working_place.leisureType = "") ? "none" : working_place.leisureType;
            string wp_name <- (working_place.buildingName = nil or working_place.buildingName = "") ? "unnamed" : working_place.buildingName;
            workPlaceString <- wp_type + " | leisure:" + wp_leisure + " | name:" + wp_name;
        } else {
            workPlaceString <- "unassigned";
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
	        pedestrianTripCounter <- pedestrianTripCounter + 1;
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
	                    else if (_origin_norm contains "mostol" or _origin_norm contains "stol") { origin_city <- "Mostoles"; }
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
	                trainTripCounter <- trainTripCounter + 1;
	            }
	            else if (formOfTransportation = "taxi") {
                    if (current_trip_id = nil) { do start_trip_log("taxi", objective); }
	                ask taxiSwitchboard {
	                    do requestTaxi(myself);
	                }
	                taxiTripCounter <- taxiTripCounter + 1;
	            }
	            else if (formOfTransportation = "car") {
                    if (current_trip_id = nil) { do start_trip_log("car", objective); }
	                do instantiate_car;
	                carTripCounter <- carTripCounter + 1;
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
	                carTripCounter <- carTripCounter + 1;
	            }
	            else if (formOfTransportation = "taxi") {
                    if (current_trip_id = nil) { do start_trip_log("taxi", objective); }
	                ask taxiSwitchboard {
	                    do requestTaxi(myself);
	                }
	                newObjective <- false;
	                taxiTripCounter <- taxiTripCounter + 1;
	            }
	            else if (formOfTransportation = "walking") {
                    if (current_trip_id = nil) { do start_trip_log("walking", objective); }
	                startJourney <- true;
	                newObjective <- false;
	                forcedWalkMode <- false;
	                pedestrianTripCounter <- pedestrianTripCounter + 1;
	            }
	        }
	    }
	}

    /////////////////////////////////////////////////////////////
    // Reflex: prepare the route and start movement
    /////////////////////////////////////////////////////////////
    reflex empezar when: startJourney {
        int attempts <- 0;
        bool route_found <- false;
        list<crossroads> walk_nodes <- crossroads where (each.isStreet or each.isZebraCrossing);
        crossroads failed_route_origin <- nil;
        crossroads failed_route_destination <- nil;
        walking_route_outcome_logged <- false;
        walking_route_attempts <- 0;

        start <- nil;
        finishPoint <- nil;
        if (!empty(walk_nodes)) {
            start <- walk_nodes closest_to self.location;
            if (the_target != nil) {
                finishPoint <- walk_nodes closest_to the_target.location;
            }
        }
        if (start != nil and finishPoint != nil) {
            attempts <- 1;
            walking_route_attempts <- 1;
            failed_route_origin <- start;
            failed_route_destination <- finishPoint;
            planned_walk_origin <- start;
            planned_walk_destination <- finishPoint;
            current_path <- path_between(streetsNetwork, start, finishPoint);
            route_found <- (current_path != nil);
        } else {
            planned_walk_origin <- start;
            planned_walk_destination <- finishPoint;
            current_path <- nil;
        }
        startJourney <- false;
        if (start != nil and finishPoint != nil) {
            isMoving <- true;
            speed <- self.speed;
            newObjective <- false;
            forcedWalkMode <- false;
            stopped <- false;
            walk_no_progress_cycles <- 0;
            last_distance_to_finish <- (finishPoint != nil) ? distance_to(self.location, finishPoint.location) : -1.0;
            if (route_found) {
                do log_route_plan_event("first_try_success", attempts);
                walking_route_outcome_logged <- true;
            } else {
                nullTTCount <- nullTTCount + 1;
            }
        } else {
            nullTTCount <- nullTTCount + 1;
            walking_route_attempts <- max(1, attempts);
            planned_walk_origin <- failed_route_origin;
            planned_walk_destination <- failed_route_destination;
            do abort_walking_trip_no_route("no_route_direct");
        }
    }

    /////////////////////////////////////////////////////////////
    // Reflex: walk the path, handling zebra crossings
    /////////////////////////////////////////////////////////////
    list<geometry> zebra_edges <- [];
    crossroads crossingNode;
    crossroads zebraCross;
    crossroads activeCrossingNode <- nil;  // Tracks the node we are currently "crossing" to manage car blocking

    action abort_walking_trip_no_route(string reason_label) {
        if (activeCrossingNode != nil) {
            activeCrossingNode.pedestrianCount <- max(0, activeCrossingNode.pedestrianCount - 1);
            if (simLogger != nil) {
                ask simLogger {
                    do log_event("CROSSWALK_EXIT," + time + "," + myself.name + "," + myself.activeCrossingNode.name + ",release_on_abort_no_route,0,0");
                }
            }
            activeCrossingNode <- nil;
        }
        isCrossing <- false;
        zebra_edges <- [];

        isMoving <- false;
        stopped <- true;
        startJourney <- false;
        finishPoint <- nil;
        current_path <- nil;
        forcedWalkMode <- false;
        newObjective <- false;
        walk_no_progress_cycles <- 0;
        last_distance_to_finish <- -1.0;
        if (!walking_route_outcome_logged) {
            do log_route_plan_event("failed_after_retries", max(1, walking_route_attempts));
            walking_route_outcome_logged <- true;
            if (simLogger != nil) {
                string failed_trip_id <- (current_trip_id = nil) ? "" : current_trip_id;
                ask simLogger {
                    do log_failed_person_walking_crossroads(
                        myself.name,
                        failed_trip_id,
                        "failed_after_retries",
                        max(1, myself.walking_route_attempts),
                        myself.planned_walk_origin,
                        myself.planned_walk_destination
                    );
                }
            }
        }

        if (simLogger != nil) {
            string details <- "agent:person_walking|mode:walking|result:aborted_no_route|reason:" + reason_label;
            ask simLogger {
                do log_event("ROUTE_EXEC," + time + "," + myself.name + ",walking," + details + ",0,0");
            }
        }
        if (current_trip_id != nil) { do end_trip_log("ABORTED_NO_ROUTE_WALK"); }
        the_target <- nil;
    }

	reflex walk when: isMoving and finishPoint != nil and (not startJourney) {
        bool continue_walk_logic <- true;
        if (!walking_route_outcome_logged and current_path = nil) {
            walking_route_attempts <- max(1, walking_route_attempts) + 1;
        }
	    if (continue_walk_logic) {
	        do goto(target: finishPoint, on: streetsNetwork, speed: speed, return_path: true, recompute_path: true);
	    }
        int walk_recovery_trigger <- int(max(5, min(10, walk_route_retry_limit)));
        int walk_recovery_pair_limit <- int(min(12, max(5, walk_route_retry_limit)));
        if (!walking_route_outcome_logged
            and current_path = nil
            and finishPoint != nil
            and the_target != nil
            and walking_route_attempts >= walk_recovery_trigger
            and (walking_route_attempts = walk_recovery_trigger or ((walking_route_attempts - walk_recovery_trigger) mod 5 = 0))) {
            float search_radius <- initialSearchRadius;
            list<crossroads> altStarts <- crossroads where (
                (each.isStreet or each.isZebraCrossing) and distance_to(each.location, self.location) < search_radius
            ) sort_by (distance_to(each.location, self.location));
            list<crossroads> altTargets <- crossroads where (
                (each.isStreet or each.isZebraCrossing) and distance_to(each.location, the_target.location) < search_radius
            ) sort_by (distance_to(each.location, the_target.location));
            int recovery_checks <- 0;
            if (empty(altStarts) and start != nil) { altStarts <- [start]; }
            if (empty(altTargets) and finishPoint != nil) { altTargets <- [finishPoint]; }
            loop altStart over: altStarts {
                if (current_path != nil or recovery_checks >= walk_recovery_pair_limit) { break; }
                loop altTarget over: altTargets {
                    if (current_path != nil or recovery_checks >= walk_recovery_pair_limit) { break; }
                    bool valid_pair <- (altStart != nil and altTarget != nil);
                    bool duplicate_current <- (altStart = start and altTarget = finishPoint);
                    if (valid_pair and !duplicate_current) {
                        recovery_checks <- recovery_checks + 1;
                        planned_walk_origin <- altStart;
                        planned_walk_destination <- altTarget;
                        current_path <- path_between(streetsNetwork, altStart, altTarget);
                        if (current_path != nil) {
                            start <- altStart;
                            finishPoint <- altTarget;
                            location <- start.location;
                            walk_no_progress_cycles <- 0;
                            last_distance_to_finish <- distance_to(self.location, finishPoint.location);
                            break;
                        }
                    }
                }
            }
        }
        if (!walking_route_outcome_logged and current_path != nil) {
            do log_route_plan_event("recovered_after_retries", max(2, walking_route_attempts));
            walking_route_outcome_logged <- true;
        }

        // Progress watchdog: if walker does not get closer for too long, abort route.
        if (continue_walk_logic and finishPoint != nil) {
            float dist_now <- distance_to(self.location, finishPoint.location);
            float progress_epsilon <- max(0.1, (speed * step * 0.02));
            bool protected_wait <- (isCrossing or activeCrossingNode != nil or waitingForTrain);
            if (protected_wait) {
                walk_no_progress_cycles <- 0;
            } else if (last_distance_to_finish < 0.0 or dist_now < (last_distance_to_finish - progress_epsilon)) {
                walk_no_progress_cycles <- 0;
            } else {
                walk_no_progress_cycles <- walk_no_progress_cycles + 1;
            }
            last_distance_to_finish <- dist_now;
            if (walk_no_progress_cycles >= walk_route_retry_limit) {
                string abort_reason <- (current_path = nil) ? "stall_with_nil_path" : "stall_without_progress";
                do abort_walking_trip_no_route(abort_reason);
                continue_walk_logic <- false;
            }
        }
        
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

        if (continue_walk_logic and finishPoint != nil) {
	        // Defensive path handling: current_path can become nil in long runs.
	        positionCurrentEdge <- -1;
	        bool path_ready <- false;
	        list<geometry> path_edges <- [];
	        list<geometry> path_vertices <- [];
	        if (current_path != nil) {
	            path_edges <- current_path.edges;
	            path_vertices <- current_path.vertices;
	            if (path_edges != nil and path_vertices != nil) {
	                path_ready <- true;
	                if (current_edge != nil) {
	                    int edge_idx <- path_edges index_of current_edge;
	                    if (edge_idx != nil) { positionCurrentEdge <- edge_idx; }
	                }
	                nullTTCount <- 0;
	            }
	        }

	        if (!path_ready) {
	            nullTTCount <- nullTTCount + 1;
	            continue_walk_logic <- false;
	        }

	        if (continue_walk_logic and path_ready) {
	        // 3. Release crossing once passed
	        if (isCrossing) {
	            if (length(self.zebra_edges) > 0 and positionCurrentEdge >= 0) {
	                geometry lastZebraEdge <- last(zebra_edges);
	                int lastZebraEdgeIndex <- path_edges index_of lastZebraEdge;
	                if (lastZebraEdgeIndex != nil and positionCurrentEdge > lastZebraEdgeIndex) {
	                    // Release the active zebra crossing counter
	                    if (activeCrossingNode != nil) {
	                        activeCrossingNode.pedestrianCount <- max(0, activeCrossingNode.pedestrianCount - 1);
	                        activeCrossingNode <- nil;
	                    }
	                    isCrossing <- false;
                        if (simLogger != nil) { ask simLogger { do log_event("CROSSWALK_EXIT," + time + "," + myself.name + ",unknown_crossing,release_on_move,0,0"); } }
	                    // Clear stored zebra edges
	                    zebra_edges <- [];
	                }
	            }
	        }
	        
	        // 1. Detect upcoming zebra crossings and store edges
	        if (positionCurrentEdge >= 0 
	            and positionCurrentEdge < (length(path_edges) - 2)
	            and (positionCurrentEdge + 2) < length(path_vertices)) {
	            
	            loop i from: (positionCurrentEdge + 1) to: (positionCurrentEdge + 2) {
	                if (i < length(path_vertices)) {
	                    zebraCross <- crossroads(path_vertices[i]);
	                    if (zebraCross.isZebraCrossing) {
	                        if (i < length(path_edges) and !(path_edges[i] in self.zebra_edges)) {
	                            self.zebra_edges <- self.zebra_edges + (path_edges[i]);
	                        }
	                    }
	                }
	            }
	            
	            // 2. Activate crossing at the next node
	            if ((positionCurrentEdge + 1) < length(path_vertices)) {
	                crossingNode <- crossroads(path_vertices[positionCurrentEdge + 1]);
	                if (crossingNode.isZebraCrossing and !isCrossing) {
	                    isCrossing <- true;
	                    activeCrossingNode <- crossingNode;
	                    crossingNode.pedestrianCount <- crossingNode.pedestrianCount + 1;
                        if (simLogger != nil and activeCrossingNode != nil) { ask simLogger { do log_event("CROSSWALK_ENTER," + time + "," + myself.name + "," + myself.activeCrossingNode.name + ",normal_entry,0,0"); } }
	                }
	            }
	        }
	        }
        }
        
        // 4. Arrival at destination
        if (finishPoint != nil and finishPoint.location = self.location) {
            if (the_target != nil) {
                location <- point(the_target);
            }
            if (!walking_route_outcome_logged) {
                do log_route_plan_event("recovered_after_retries", max(2, walking_route_attempts));
                walking_route_outcome_logged <- true;
            }
            isMoving <- false;
            walk_no_progress_cycles <- 0;
            last_distance_to_finish <- -1.0;
            
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
                stationString <- (the_target.buildingName = "Leganes") 
                    ? "Leganes Central" 
                    : the_target.buildingName + ((the_final_target.buildingName = "Madrid") ? " - Via 1" : " - Via 2");
                crossroads station <- one_of(crossroads where (
                    each.isTrainStation and each.nameTrainStation = ((the_target.buildingName = "Leganes") 
                        ? "Leganes Central" 
                        : the_target.buildingName) + ((the_final_target.buildingName = "Madrid" or the_final_target.buildingName = "Getafe") 
                        ? " - Via 1" 
                        : " - Via 2")
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
            startJourney <- false;
            stopped <- true;
            if (!boardingTrainAtStation) {
                do end_trip_log("COMPLETED");
            }
            the_target <- nil;
            isCrossing <- false;
            zebra_edges <- [];
            planned_walk_origin <- nil;
            planned_walk_destination <- nil;
            walking_route_attempts <- 0;
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
                initialCrossroad <- (crossroads where !(each.crossroadsNoInitialLocation) at_distance (initialSearchRadius #meters) closest_to(myself.location));
                if (initialCrossroad = nil) {
                    initialCrossroad <- (crossroads where !(each.crossroadsNoInitialLocation) closest_to(myself.location));
                }
                targetCrossroads <- (crossroads where !(each.crossroadsNoInitialLocation) at_distance (initialSearchRadius #meters) closest_to(myself.the_target));
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
    list<electricCars> registeredTaxis <- [];
    int freeTaxis <- 0;
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
        write "Passenger request from " + p + " added to pending trips queue.";
        return true;
    }

    // Local helper to keep switchboard registry coherent from within switchboard scope
    action refresh_taxi_registry {
        registeredTaxis <- electricCars where (each != nil and !dead(each));
        freeTaxis <- length(registeredTaxis where (each.lowBattery = false and each.isAvailable = true and each.isWandering));
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
    reflex assignClient when: length(pendingTrips) > 0 {
        registeredTaxis <- registeredTaxis where (each != nil and !dead(each));
        list<electricCars> taxi_pool <- (length(registeredTaxis) > 0)
            ? registeredTaxis
            : (electricCars where (each != nil and !dead(each)));
        // Get list of available taxis: not low battery, marked as isAvailable, and wandering
        list<electricCars> availableTaxis <- taxi_pool where (
            each.lowBattery = false and each.isAvailable = true and each.isWandering
        );
        freeTaxis <- length(availableTaxis);
        if (length(availableTaxis) = 0) {
            write "No taxis are currently available.";
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
                        t.targetCrossroads <- (crossroads where !each.crossroadsNoInitialLocation at_distance (initialSearchRadius #meters) closest_to selectedTrip.passenger.location);
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
                        
                        write "Taxi " + t + " assigned to passenger " + selectedTrip.passenger + " (mode " + assignmentMode + ").";
                    }
                }
            }
        }
        do refresh_taxi_registry;
    }
}

species SimulationLogger {
    list<string> trip_logs <- [];
    list<string> event_logs <- [];
    
    // Configurable output file paths
    string trips_file <- "trips.csv";
    string events_file <- "events.csv";
    string failed_person_walking_crossroads_file <- "failed_person_walking_crossroads.csv";
    string failed_car_trip_crossroads_file <- "failed_car_trip_crossroads.csv";
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
        save [
            "time",
            "person_id",
            "trip_id",
            "result",
            "attempts",
            "origin_crossroad",
            "origin_x",
            "origin_y",
            "destination_crossroad",
            "destination_x",
            "destination_y"
        ] to: failed_person_walking_crossroads_file format: "csv" rewrite: true;
        save [
            "time",
            "person_id",
            "trip_id",
            "vehicle_id",
            "result",
            "attempts",
            "origin_crossroad",
            "origin_x",
            "origin_y",
            "destination_crossroad",
            "destination_x",
            "destination_y"
        ] to: failed_car_trip_crossroads_file format: "csv" rewrite: true;
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

    action log_failed_person_walking_crossroads(string person_id, string trip_id, string result_label, int attempts, crossroads origin_node, crossroads destination_node) {
        string origin_name <- (origin_node = nil or origin_node.name = nil) ? "" : origin_node.name;
        string origin_x <- (origin_node = nil) ? "" : string(origin_node.location.x);
        string origin_y <- (origin_node = nil) ? "" : string(origin_node.location.y);
        string destination_name <- (destination_node = nil or destination_node.name = nil) ? "" : destination_node.name;
        string destination_x <- (destination_node = nil) ? "" : string(destination_node.location.x);
        string destination_y <- (destination_node = nil) ? "" : string(destination_node.location.y);
        save [
            time,
            person_id,
            trip_id,
            result_label,
            max(1, attempts),
            origin_name,
            origin_x,
            origin_y,
            destination_name,
            destination_x,
            destination_y
        ] to: failed_person_walking_crossroads_file format: "csv" rewrite: false;
    }

    action log_failed_car_trip_crossroads(string person_id, string trip_id, string vehicle_id, string result_label, int attempts, crossroads origin_node, crossroads destination_node) {
        string origin_name <- (origin_node = nil or origin_node.name = nil) ? "" : origin_node.name;
        string origin_x <- (origin_node = nil) ? "" : string(origin_node.location.x);
        string origin_y <- (origin_node = nil) ? "" : string(origin_node.location.y);
        string destination_name <- (destination_node = nil or destination_node.name = nil) ? "" : destination_node.name;
        string destination_x <- (destination_node = nil) ? "" : string(destination_node.location.x);
        string destination_y <- (destination_node = nil) ? "" : string(destination_node.location.y);
        save [
            time,
            person_id,
            trip_id,
            vehicle_id,
            result_label,
            max(1, attempts),
            origin_name,
            origin_x,
            origin_y,
            destination_name,
            destination_x,
            destination_y
        ] to: failed_car_trip_crossroads_file format: "csv" rewrite: false;
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
        do log_population_metric("household_generation_adjustment_count", "size_fillers_added_people", householdSizeFillersAdded, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "size_overflow_removed_people", householdSizeOverflowRemoved, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "size_adjusted_households", householdSizeAdjustedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "size_fill_adjusted_households", householdSizeFillAdjustedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "size_overflow_adjusted_households", householdSizeOverflowAdjustedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_rectified_households", householdPostprocessRectifiedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_rectified_people", householdPostprocessRectifiedPersons, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_home_rectified_households", householdPostprocessHomeRectifiedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_home_rectified_people", householdPostprocessHomeRectifiedPersons, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_partner_rectified_households", householdPostprocessPartnerRectifiedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_partner_rectified_people", householdPostprocessPartnerRectifiedPersons, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_father_rectified_households", householdPostprocessFatherRectifiedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_father_rectified_people", householdPostprocessFatherRectifiedPersons, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_mother_rectified_households", householdPostprocessMotherRectifiedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_mother_rectified_people", householdPostprocessMotherRectifiedPersons, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_children_rectified_households", householdPostprocessChildrenRectifiedHouseholds, "count", "simulation");
        do log_population_metric("household_generation_adjustment_count", "postprocess_children_rectified_people", householdPostprocessChildrenRectifiedPersons, "count", "simulation");
        do log_population_metric("household_generation_adjustment_share", "size_adjusted_households", (total_households > 0) ? householdSizeAdjustedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "size_fill_adjusted_households", (total_households > 0) ? householdSizeFillAdjustedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "size_overflow_adjusted_households", (total_households > 0) ? householdSizeOverflowAdjustedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_rectified_households", (total_households > 0) ? householdPostprocessRectifiedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_rectified_people", (total_people > 0) ? householdPostprocessRectifiedPersons / total_people : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_home_rectified_households", (total_households > 0) ? householdPostprocessHomeRectifiedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_home_rectified_people", (total_people > 0) ? householdPostprocessHomeRectifiedPersons / total_people : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_partner_rectified_households", (total_households > 0) ? householdPostprocessPartnerRectifiedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_partner_rectified_people", (total_people > 0) ? householdPostprocessPartnerRectifiedPersons / total_people : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_father_rectified_households", (total_households > 0) ? householdPostprocessFatherRectifiedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_father_rectified_people", (total_people > 0) ? householdPostprocessFatherRectifiedPersons / total_people : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_mother_rectified_households", (total_households > 0) ? householdPostprocessMotherRectifiedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_mother_rectified_people", (total_people > 0) ? householdPostprocessMotherRectifiedPersons / total_people : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_children_rectified_households", (total_households > 0) ? householdPostprocessChildrenRectifiedHouseholds / total_households : 0.0, "share", "simulation");
        do log_population_metric("household_generation_adjustment_share", "postprocess_children_rectified_people", (total_people > 0) ? householdPostprocessChildrenRectifiedPersons / total_people : 0.0, "share", "simulation");

        int blueprint_pool_size <- length(populationBlueprintPool);
        int blueprint_consumed <- max(0, blueprint_pool_size - populationBlueprintAvailable);
        int blueprint_total_hits <- blueprintExactMatches + blueprintAgeOnlyMatches + blueprintGenderOnlyMatches + blueprintAnyMatches;
        do log_population_metric("blueprint_usage_count", "get_person_calls", populationGetPersonCalls, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "pull_attempts", blueprintPullAttempts, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "exact_matches", blueprintExactMatches, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "age_only_matches", blueprintAgeOnlyMatches, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "gender_only_matches", blueprintGenderOnlyMatches, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "any_matches", blueprintAnyMatches, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "total_hits", blueprint_total_hits, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "misses", blueprintMisses, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "fallback_person_generations", blueprintFallbackPersonGenerations, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "blueprint_rejected_non_intersecting_age_count", blueprintRejectedNonIntersectingAgeCount, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "pool_size", blueprint_pool_size, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "pool_consumed", blueprint_consumed, "count", "simulation");
        do log_population_metric("blueprint_usage_count", "pool_remainder", populationBlueprintAvailable, "count", "simulation");
        do log_population_metric("blueprint_usage_share", "exact_matches", (blueprintPullAttempts > 0) ? blueprintExactMatches / blueprintPullAttempts : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "age_only_matches", (blueprintPullAttempts > 0) ? blueprintAgeOnlyMatches / blueprintPullAttempts : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "gender_only_matches", (blueprintPullAttempts > 0) ? blueprintGenderOnlyMatches / blueprintPullAttempts : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "any_matches", (blueprintPullAttempts > 0) ? blueprintAnyMatches / blueprintPullAttempts : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "misses", (blueprintPullAttempts > 0) ? blueprintMisses / blueprintPullAttempts : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "fallback_person_generations", (populationGetPersonCalls > 0) ? blueprintFallbackPersonGenerations / populationGetPersonCalls : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "blueprint_rejected_non_intersecting_age_share", (blueprintPullAttempts > 0) ? blueprintRejectedNonIntersectingAgeCount / blueprintPullAttempts : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "pool_consumed", (blueprint_pool_size > 0) ? blueprint_consumed / blueprint_pool_size : 0.0, "share", "simulation");
        do log_population_metric("blueprint_usage_share", "pool_remainder", (blueprint_pool_size > 0) ? populationBlueprintAvailable / blueprint_pool_size : 0.0, "share", "simulation");
        do log_population_metric("hard_constraints", "hard_constraint_violations_final", hardConstraintViolationsFinal, "count", "simulation");
        do log_population_metric("hard_constraints", "household_hard_fallback_count", householdHardFallbackCount, "count", "simulation");
        do log_population_metric("hard_constraints", "household_hard_fallback_share", (total_households > 0) ? householdHardFallbackCount / total_households : 0.0, "share", "simulation");
        do log_population_metric("hard_constraints", "person_creation_soft_relax_stage_1_count", personCreationSoftRelaxStage1Count, "count", "simulation");
        do log_population_metric("hard_constraints", "person_creation_soft_relax_stage_2_count", personCreationSoftRelaxStage2Count, "count", "simulation");
        do log_population_metric("hard_constraints", "person_creation_soft_relax_stage_3_count", personCreationSoftRelaxStage3Count, "count", "simulation");
        do log_population_metric("couple_gap_match", "target_bucket_hits", coupleGapTargetBucketHits, "count", "simulation");
        do log_population_metric("couple_gap_match", "achieved_on_target", coupleGapAchievedOnTarget, "count", "simulation");
        do log_population_metric("couple_gap_match", "achieved_on_target_share", (coupleGapTargetBucketHits > 0) ? coupleGapAchievedOnTarget / coupleGapTargetBucketHits : 0.0, "share", "simulation");
        do log_population_metric("couple_gap_match", "sampling_retries", coupleGapSampleRetries, "count", "simulation");
        do log_population_metric("couple_gap_match", "quota_spillover_count", coupleGapQuotaSpilloverCount, "count", "simulation");
        loop gb over: ["0-4", "5-9", "10-14", "15+"] {
            int quota_target <- (coupleGapQuotaTargetCounts[gb] = nil) ? 0 : coupleGapQuotaTargetCounts[gb];
            int quota_used <- (coupleGapQuotaUsedCounts[gb] = nil) ? 0 : coupleGapQuotaUsedCounts[gb];
            do log_population_metric("couple_gap_match", "quota_target_" + gb, quota_target, "count", "simulation");
            do log_population_metric("couple_gap_match", "quota_used_" + gb, quota_used, "count", "simulation");
        }
        loop reason over: keys(householdHardFallbackReasonCounts) {
            int reason_count <- (householdHardFallbackReasonCounts[reason] = nil) ? 0 : householdHardFallbackReasonCounts[reason];
            do log_population_metric("hard_fallback_reason_count", reason, reason_count, "count", "simulation");
        }

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

        list<Person> couple_leads <- Person where (
            each.partner != nil and
            each.name != nil and
            each.partner.name != nil and
            each.name < each.partner.name
        );
        int total_couples <- length(couple_leads);
        do log_population_metric("population", "total_couples", total_couples, "count", "simulation");

        int heterosexual_count <- 0;
        loop cp over: couple_leads {
            string cp_gender_norm <- "female";
            string partner_gender_norm <- "female";

            if (cp.gender != nil) {
                string cg <- lower_case(cp.gender as string);
                if (cg = "female" or cg contains "fem" or cg contains "muj") { cp_gender_norm <- "female"; }
                else if (cg = "male" or cg contains "hom" or cg contains "varon" or (cg contains "male" and !(cg contains "female"))) { cp_gender_norm <- "male"; }
            }
            if (cp.partner != nil and cp.partner.gender != nil) {
                string pg <- lower_case(cp.partner.gender as string);
                if (pg = "female" or pg contains "fem" or pg contains "muj") { partner_gender_norm <- "female"; }
                else if (pg = "male" or pg contains "hom" or pg contains "varon" or (pg contains "male" and !(pg contains "female"))) { partner_gender_norm <- "male"; }
            }

            if (cp_gender_norm != partner_gender_norm) {
                heterosexual_count <- heterosexual_count + 1;
            }
        }
        int homosexual_count <- max(0, total_couples - heterosexual_count);
        float heterosexual_share <- (total_couples > 0) ? heterosexual_count / total_couples : 0.0;
        float homosexual_share <- (total_couples > 0) ? homosexual_count / total_couples : 0.0;
        do log_population_metric("orientation_count", "heterosexual", heterosexual_count, "count", "simulation");
        do log_population_metric("orientation_count", "homosexual", homosexual_count, "count", "simulation");
        do log_population_metric("orientation", "heterosexual", heterosexual_share, "share", "simulation");
        do log_population_metric("orientation", "homosexual", homosexual_share, "share", "simulation");

        map<string, float> couple_gap_counts <- map<string, float>(map([
            "0-4" :: 0.0,
            "5-9" :: 0.0,
            "10-14" :: 0.0,
            "15+" :: 0.0
        ]));
        loop cp over: couple_leads {
            float age_gap <- abs(cp.age - cp.partner.age);
            string gap_bucket <- "15+";
            if (age_gap < 5.0) { gap_bucket <- "0-4"; }
            else if (age_gap < 10.0) { gap_bucket <- "5-9"; }
            else if (age_gap < 15.0) { gap_bucket <- "10-14"; }
            float current_count <- (couple_gap_counts[gap_bucket] = nil) ? 0.0 : couple_gap_counts[gap_bucket];
            couple_gap_counts[gap_bucket] <- current_count + 1.0;
        }
        loop gap_bucket over: ["0-4", "5-9", "10-14", "15+"] {
            float gap_count <- (couple_gap_counts[gap_bucket] = nil) ? 0.0 : couple_gap_counts[gap_bucket];
            float gap_share <- (total_couples > 0) ? gap_count / total_couples : 0.0;
            do log_population_metric("couple_age_gap_count", gap_bucket, gap_count, "count", "simulation");
            do log_population_metric("couple_age_gap", gap_bucket, gap_share, "share", "simulation");
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
        loop gap_bucket over: ["0-4", "5-9", "10-14", "15+"] {
            float target_gap <- (coupleAgeGapProbabilities[gap_bucket] = nil) ? 0.0 : coupleAgeGapProbabilities[gap_bucket];
            do log_reference_metric("couple_age_gap_target", gap_bucket, target_gap, "share", "db");
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

// Experiment "Leganes" (full version): configures visualization, simulation, vehicles, buses, transport, and outputs
experiment Leganes type: gui {
    // GIS and visualization parameters
    parameter "Display in 2D (true) or 3D (false):" var: render3D category: "Visualization";
    parameter "Show road direction arrows (true) or hide them (false):" var: watchDirections category: "Visualization";
    parameter "Enable enhanced vehicle appearance (true/false):" var: carsEnhancedAppearance category: "Visualization";
    parameter "Show charging station connector labels (true/false):" var: showTextChargingPoints category: "Visualization";
    
    // Simulation step size
    parameter "Simulation step duration (minutes):" var: step <- step min: 0.015 #minutes max: 0.333333 #minutes category: "Simulation";
    
    // Autonomous taxi fleet settings
    parameter "Number of electric taxis:" var: numberOfElectricCars <- 1 min: 0 max: 2000 category: "Autonomous Taxi Fleet";
    parameter "Initial search radius (meters):" var: initialSearchRadius <- 500.0 min: 50.0 max: 5000.0 category: "Autonomous Taxi Fleet";
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


// Experiment "CO2 Study": focuses on analyzing CO2 consumption
experiment CO2Study type: gui {
    // GIS and visualization parameters
    parameter "Display in 2D (true) or 3D (false):" var: render3D category: "Visualization";
    parameter "Show road direction arrows (true/false):"      var: watchDirections category: "Visualization";
    parameter "Enable enhanced vehicle appearance (true/false):" var: carsEnhancedAppearance category: "Visualization";
    parameter "Show charging station connector labels (true/false):" var: showTextChargingPoints category: "Visualization";
    
    // Simulation time step
    parameter "Simulation step duration (minutes):" var: step <- step min: 0.015 #minutes max: 0.333333 #minutes category: "Simulation";
    
    // Autonomous taxi fleet settings
    parameter "Number of electric taxis:" var: numberOfElectricCars <- 1 min: 0 max: 2000 category: "Autonomous Taxi Fleet";
    parameter "Initial search radius (meters):"   var: initialSearchRadius <- 500.0 min: 50.0 max: 5000.0 category: "Autonomous Taxi Fleet";
        
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


// Experiment "AgeDistribution": study of population age distribution
experiment AgeDistribution type: gui {
    // GIS and visualization parameters
    parameter "Display in 2D (true) or 3D (false):"                 var: render3D            category: "Visualization";
    parameter "Show road direction arrows (true/false):"           var: watchDirections     category: "Visualization";
    parameter "Enable enhanced vehicle appearance (true/false):"   var: carsEnhancedAppearance category: "Visualization";
    parameter "Show charging station connector labels (true/false):" var: showTextChargingPoints category: "Visualization";
    
    // Simulation time step
    parameter "Simulation step duration (minutes):"                var: step <- step        min: 0.015 #minutes max: 0.333333 #minutes category: "Simulation";
    
    // Autonomous taxi fleet settings
    parameter "Number of electric taxis:"                          var: numberOfElectricCars <- 1 min: 0 max: 2000      category: "Autonomous Taxi Fleet";
    parameter "Initial search radius (meters):"                    var: initialSearchRadius <- 500.0 min: 50.0 max: 5000.0 category: "Autonomous Taxi Fleet";
    
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
