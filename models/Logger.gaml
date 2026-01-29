species SimulationLogger {
    list<string> trip_logs <- [];
    list<string> event_logs <- [];
    
    // Configurable output file paths
    string trips_file <- "trips.csv";
    string events_file <- "events.csv";

    // Setup function to initialize files with headers
    action initialize_logs {
        save "person_id,trip_id,purpose,mode,origin_type,origin_x,origin_y,dest_type,dest_x,dest_y,start_time,end_time,duration,status,path_cost,real_distance,wait_time" 
            to: trips_file type: "text" rewrite: true;
        save "event_type,time,entity_id,related_id,details,extra_1,extra_2" 
            to: events_file type: "text" rewrite: true;
    }

    action log_trip(string log_entry) {
        trip_logs <- trip_logs + log_entry;
    }
    
    action log_event(string log_entry) {
        event_logs <- event_logs + log_entry;
    }
    
    reflex flush_logs when: (cycle mod 10 = 0) {
        if (!empty(trip_logs)) {
            loop t over: trip_logs {
                save t to: trips_file type: "text" rewrite: false;
            }
            trip_logs <- [];
        }
        
        if (!empty(event_logs)) {
            loop e over: event_logs {
                save e to: events_file type: "text" rewrite: false;
            }
            event_logs <- [];
        }
    }
}
