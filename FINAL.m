% Set the COM port of the Shimmer device 
comPort = '4';  
shimmer = ShimmerHandleClass(comPort); 

% Set the sampling rate and other configuration parameters 
samplingRate = 1000;  % Sampling rate (Hz)
duration = 6300;      % Duration in seconds (105 minutes)

% Open a CSV file for writing raw EMG data
csvFileName = 'raw_emg_data_105min.csv';
csvFile = fopen(csvFileName, 'w');
fprintf(csvFile, 'ElapsedTime(seconds),RawEMGAmplitude(mV)\n');  % Write header

% Initialize arrays to store data
allSignalData = [];  % To store raw signal data
filteredSignalData = []; % To store filtered signal data (for RMS)
rmsValues = [];  % To store calculated RMS values
rmsSlope = [];  % To store RMS slope
elapsedTime = [];    % To store actual time

% Design a Butterworth bandpass filter (10-200 Hz)
lowCutoff = 10;  % Lower cutoff frequency (Hz)
highCutoff = 200;  % Higher cutoff frequency (Hz)
[b_bp, a_bp] = butter(1 , [lowCutoff highCutoff] / (samplingRate / 2), 'bandpass');  % 1st order filter

% RMS parameters
windowSize = samplingRate; % 1 second of data (1000 samples)

% Initialize computation time tracking variables
computationTimes = [];
totalComputationTime = 0;

try
    % Connect to the Shimmer device 
    if (shimmer.connect()) 
        disp('Shimmer connected'); 

        % Start streaming data 
        shimmer.start; 
        disp('Shimmer started'); 

        % Create figures for plotting 
        figure; 

        % Plot for RMS values
        subplot(2,1,1);
        rawPlot = plot(NaN, NaN, 'b');  % Blue line for RMS of filtered data
        title('Filtered EMG Data with RMS'); 
        xlabel('Time (seconds)');
        ylabel('RMS Value (mV)');
        xlim([0 duration]);  
        ylim([0 1]);  % Adjust Y-axis limits as needed
        grid on;  

        % Plot for RMS slope
        subplot(2,1,2);
        slopePlot = plot(NaN, NaN, 'r');  % Red line for RMS slope
        title('RMS Slope'); 
        xlabel('Time (seconds)');
        ylabel('Slope (mV/s)');
        xlim([0 duration]);  
        ylim([-0.5 0.5]);  % Adjust Y-axis limits as needed
        grid on;

        % Start a timer
        startTime = tic;     

        % Main loop for real-time data acquisition and processing 
        while ishandle(gcf) && toc(startTime) < duration 
            % Start timing computation for this loop
            loopStartTime = tic;

            % Update elapsed time at the start of each loop
            currentElapsedTime = toc(startTime);

            % Read data from the Shimmer device 
            [data, timestamp] = shimmer.getdata('c'); 

            if ~isempty(data)
                % Access the EMG data (assuming it is in column 4)
                rawSignalData = data(:, 4);  

                % Append raw data to allSignalData
                allSignalData = [allSignalData; rawSignalData];

                % Apply Butterworth bandpass filter to the raw EMG signal
                filteredSignal = filtfilt(b_bp, a_bp, rawSignalData);
                
                % Append filtered signal data for RMS calculation
                filteredSignalData = [filteredSignalData; filteredSignal];
                
                % Calculate RMS for the last second (1 second window)
                if length(filteredSignalData) >= windowSize
                    rmsValue = sqrt(mean(filteredSignalData(end-windowSize+1:end).^2));  % RMS for the last second
                    rmsValues = [rmsValues; rmsValue];

                    % Update elapsed time with actual duration
                    elapsedTime = [elapsedTime; currentElapsedTime];  % Update time with each new sample

                    % Calculate RMS slope if there are at least 2 RMS values
                    if length(rmsValues) > 1
                        dt = elapsedTime(end) - elapsedTime(end-1);  % Time difference
                        drms = rmsValues(end) - rmsValues(end-1);  % RMS difference
                        rmsSlope = [rmsSlope; drms / dt];  % Slope calculation
                    else
                        rmsSlope = [rmsSlope; 0];  % Default slope if not enough data
                    end

                    % Check if RMS slope is in the desired range (0.345 < slope < 0.36)
                    if rmsSlope(end) > 0.345 && rmsSlope(end) < 0.36
                        % Create fullscreen pop-up with blank background
                        screenSize = get(0, 'ScreenSize');  % Get screen dimensions
                        fig = figure('Name', 'Perhatian', 'NumberTitle', 'off', ...
                            'MenuBar', 'none', 'ToolBar', 'none', 'Color', 'yellow', ...
                            'Units', 'pixels', 'Position', screenSize, 'WindowStyle', 'modal');

                        annotation('textbox', [0, 0, 1, 1], ... % Cover the entire figure window
                            'String', 'Perhatian, apakah anda lelah?', ...
                            'FontSize', 72, 'EdgeColor', 'none', 'BackgroundColor', 'yellow', ...
                            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
                        disp('Warning: RMS slope exceeded threshold!');
                    end
                end

                % Write raw data to the CSV file
                for i = 1:length(rawSignalData)
                    fprintf(csvFile, '%.4f,%.4f\n', currentElapsedTime, rawSignalData(i));
                end

                % Update plots with new data
                if length(rmsValues) == length(elapsedTime)
                    % Update RMS plot
                    subplot(2,1,1);
                    set(rawPlot, 'XData', elapsedTime, 'YData', rmsValues);
                    xlim([0 currentElapsedTime]); 
                end

                if length(rmsSlope) == length(elapsedTime)
                    % Update RMS slope plot
                    subplot(2,1,2);
                    set(slopePlot, 'XData', elapsedTime, 'YData', rmsSlope);
                    xlim([0 currentElapsedTime]); 
                end

                drawnow;
            else
                disp('No data received, waiting...');
            end 

            % End timing computation for this loop
            loopElapsedTime = toc(loopStartTime);
            computationTimes = [computationTimes; loopElapsedTime];
            totalComputationTime = totalComputationTime + loopElapsedTime;

            pause(0.2);  % Pause to match real-time display
        end 

        shimmer.disconnect(); 
        disp('Shimmer disconnected');  
    else
        error('Failed to connect to Shimmer device.');
    end

catch ME
    % Handle any error and ensure data is saved
    disp('An error occurred:');
    disp(ME.message);
end

% Calculate and display average computation time
if ~isempty(computationTimes)
    avgComputationTime = mean(computationTimes);
    disp(['Average computation time per window: ', num2str(avgComputationTime), ' seconds']);
end

% Ensure CSV file is closed and data is saved
if ~isempty(csvFile)
    fclose(csvFile);
    disp('Raw data saved to CSV.');
end

% Save data to .mat file as well
save('raw_emg_data_105min.mat', 'allSignalData', 'filteredSignalData', 'rmsValues', 'rmsSlope', 'elapsedTime'); 
disp('Raw data also saved to .mat file.');
