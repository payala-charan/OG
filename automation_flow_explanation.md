# Utilization Report Automation Flow

This document outlines the end-to-end background process for scheduling, downloading, and validating Excel utilization reports from "App 1".

## Overview Flowchart

```mermaid
flowchart TD
    %% Frontend Setup Phase
    subgraph "Frontend Dashboard"
        A[User configures schedule\n(Time, Frequency)] --> B[AutomationSchedulesController]
        B -->|Saves| DB1[(AutomationSchedule)]
        Tracker[Global Batch Tracker UI]
    end

    %% Scheduling Phase
    subgraph "Background Scheduler"
        SysJob((SystemSchedulerJob\nRuns Periodically)) -- Checks active schedules --> DB1
        SysJob -- Creates Pending Batch --> DB2[(AutomationBatch)]
        SysJob -- Enqueues --> Dispatcher[BatchDispatcherJob]
        SysJob -- Updates next_run_at --> DB1
    end

    %% Dispatch Phase (Scaling out)
    subgraph "Job Dispatcher"
        Dispatcher -- Iterates 100 permutations\n(10 Groups x 2 Teams x 5 Quarters) --> DB3[(AutomationBatchItem)]
        Dispatcher -- Enqueues w/ 60s staggered delays --> ItemJob[AutoValidationItemJob]
    end

    %% Validation Phase
    subgraph "Execution & Validation Pipeline"
        ItemJob -- Calls --> Service[AutoValidationService]
        Service -- 1. Fetches Excel --> App1[App 1 API Endpoint]
        App1 -- 2. Downloads .xlsx --> FileSys[(atm_files/utilization_reports/)]
        Service -- 3. Builds UploadedFile --> FileSys
        Service -- 4. Passes file --> Processor[ValidationProcessor]
        Processor -- Validates data --> Processor
        Processor -- Completes --> ItemJob
    end

    %% Metric Updates
    ItemJob -- 5. Updates status (completed/failed) --> DB3
    ItemJob -- 6. Increments counter --> DB2
    
    DB2 -. Updates UI .-> Tracker
    DB3 -. Updates UI .-> Tracker
```

## Step-by-Step Breakdown

### 1. User Setup (Frontend -> Controller)
The user defines a time (e.g., `09:00 AM`) and frequency (`daily`, `weekly`, `monthly`) on the dashboard. The `AutomationSchedulesController` calculates the `next_run_at` timestamp and saves this as an `AutomationSchedule` record in the database.

### 2. Schedule Triggering (`SystemSchedulerJob`)
A periodic background cron task routinely executes `SystemSchedulerJob`. 
- It queries the database for `AutomationSchedule` records that are active and whose `next_run_at` is due (i.e. `<= Time.current`).
- For every eligible schedule, it initializes an `AutomationBatch` record with a `pending` status.
- It then enqueues a `BatchDispatcherJob` to handle the batch and updates the `next_run_at` on the `AutomationSchedule` based on the frequency for the next cycle.

### 3. Preparation & Dispatching (`BatchDispatcherJob`)
Because the external server ("App 1") might block simultaneous requests, the dispatcher handles execution spacing.
- It loops through 100 permutations representing different filtering combinations: 10 `generic_name_group`s, 2 `team_id`s, and 5 `quarter`s.
- For each permutation, it saves an `AutomationBatchItem` representing that specific validation task.
- It schedules an `AutoValidationItemJob` for each item. **Crucially, it uses a delay counter**, adding an incremental 60-second delay for each subsequent job (`(delay_counter * 60).seconds`). This guarantees requests are staggered by 1 minute, respecting App 1's API rate limits.

### 4. Fetching & Validating Data (`AutoValidationItemJob` -> `AutoValidationService` -> `ValidationProcessor`)
When an `AutoValidationItemJob` starts its execution (after its designated delay):
- It updates the item's status to `running`.
- It invokes the `AutoValidationService`, passing along the group, team, and quarter criteria.
  - **`AutoValidationService`** issues an HTTP GET request to `http://localhost:3000/api/utilization_report_export` containing the query parameters.
  - The downloaded raw excel response is saved persistently into `Rails.root/atm_files/utilization_reports/`.
  - The service encapsulates this generated `.xlsx` into an `ActionDispatch::Http::UploadedFile` object to mimic a user file upload.
- This `UploadedFile` object is handed to the **`ValidationProcessor`**, which performs the heavy duty parsing and cross-referencing against internal database records.

### 5. Tracking & UI Real-Time Updates
Once the `ValidationProcessor` handles the data:
- The `AutoValidationItemJob` marks the `AutomationBatchItem` as `completed` (or `failed` with error messages if exceptions were raised).
- It safely increments the `completed_jobs` and `failed_jobs` counters on the parent `AutomationBatch` using a transaction/lock mechanism.
- If the batch has processed all 100 items, it updates the batch's final status (`completed` or `partially_failed`).
- Your frontend Dashboard periodically reads these `AutomationBatch` and `AutomationBatchItem` rows to populate the Global Batch Tracker, letting users seamlessly visualize progress, completions, and bottlenecks.
