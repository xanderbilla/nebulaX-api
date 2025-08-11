package com.example.demo.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.mediaconvert.MediaConvertClient;
import software.amazon.awssdk.services.mediaconvert.model.*;

import java.util.Map;

/**
 * Service for handling AWS MediaConvert operations.
 * Creates transcoding jobs to convert videos to HLS format.
 * 
 * @author Xander Billa
 * @since August 11, 2025
 */
@Service
@Lazy  // Lazy initialization to avoid blocking Spring startup
public class MediaConvertService {

    private static final Logger logger = LoggerFactory.getLogger(MediaConvertService.class);

    @Value("${S3_VIDEOS_BUCKET}")
    private String sourceS3Bucket;

    @Value("${S3_TRANSCODED_BUCKET}")
    private String destinationS3Bucket;

    @Value("${MEDIACONVERT_ROLE_ARN}")
    private String mediaConvertRoleArn;

    private final MediaConvertClient mediaConvertClient;

    public MediaConvertService() {
        // Create MediaConvert client with lazy endpoint initialization
        this.mediaConvertClient = MediaConvertClient.builder().build();
        logger.info("MediaConvert service initialized (endpoint will be resolved on first use)");
    }

    /**
     * Gets MediaConvert endpoint with retry logic for rate limiting.
     */
    private String getMediaConvertEndpoint() {
        int maxRetries = 3;
        int retryCount = 0;
        
        while (retryCount < maxRetries) {
            try {
                DescribeEndpointsResponse endpointsResponse = mediaConvertClient.describeEndpoints(
                    DescribeEndpointsRequest.builder().build()
                );
                return endpointsResponse.endpoints().get(0).url();
            } catch (TooManyRequestsException e) {
                retryCount++;
                long backoffMs = 1000L * retryCount; // 1s, 2s, 3s backoff
                logger.warn("MediaConvert rate limited, retrying in {}ms (attempt {}/{})", 
                           backoffMs, retryCount, maxRetries);
                
                if (retryCount >= maxRetries) {
                    throw new RuntimeException("Failed to get MediaConvert endpoint after " + maxRetries + " retries", e);
                }
                
                try {
                    Thread.sleep(backoffMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("Interrupted while waiting for retry", ie);
                }
            }
        }
        
        throw new RuntimeException("Failed to get MediaConvert endpoint");
    }

    /**
     * Creates a MediaConvert transcoding job for video or trailer with retry logic.
     * 
     * @param sourceS3Bucket the source S3 bucket
     * @param sourceObjectKey the source object key
     * @param isTrailer whether this is a trailer file
     * @return the job ID
     */
    public String createTranscodingJob(String sourceS3Bucket, String sourceObjectKey, boolean isTrailer) {
        int maxRetries = 3;
        int retryCount = 0;
        
        while (retryCount < maxRetries) {
            try {
                return createJobInternal(sourceS3Bucket, sourceObjectKey, isTrailer);
            } catch (TooManyRequestsException e) {
                retryCount++;
                long backoffMs = 2000L * retryCount; // 2s, 4s, 6s backoff
                logger.warn("MediaConvert rate limited for job creation, retrying in {}ms (attempt {}/{})", 
                           backoffMs, retryCount, maxRetries);
                
                if (retryCount >= maxRetries) {
                    logger.error("Failed to create MediaConvert job after {} retries due to rate limiting", maxRetries);
                    throw new RuntimeException("MediaConvert job creation failed after " + maxRetries + " retries due to rate limiting", e);
                }
                
                try {
                    Thread.sleep(backoffMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("Interrupted while waiting for retry", ie);
                }
            } catch (Exception e) {
                logger.error("Failed to create MediaConvert job for {}", sourceObjectKey, e);
                throw new RuntimeException("MediaConvert job creation failed", e);
            }
        }
        
        throw new RuntimeException("Failed to create MediaConvert job");
    }

    /**
     * Internal method to create the MediaConvert job.
     */
    private String createJobInternal(String sourceS3Bucket, String sourceObjectKey, boolean isTrailer) {
        // Get endpoint and create client with endpoint override
        String endpoint = getMediaConvertEndpoint();
        MediaConvertClient clientWithEndpoint = MediaConvertClient.builder()
            .endpointOverride(java.net.URI.create(endpoint))
            .build();

        try {
            String inputS3Uri = String.format("s3://%s/%s", sourceS3Bucket, sourceObjectKey);
            
            // Create output path - maintain the same structure but change extension
            String outputPath = sourceObjectKey;
            if (outputPath.lastIndexOf('.') > 0) {
                outputPath = outputPath.substring(0, outputPath.lastIndexOf('.'));
            }
            String outputS3Uri = String.format("s3://%s/%s", destinationS3Bucket, outputPath);
            
            logger.info("Creating MediaConvert job: input={}, output={}, isTrailer={}", 
                    inputS3Uri, outputS3Uri, isTrailer);

            // Create input with audio selector
            AudioSelector audioSelector = AudioSelector.builder()
                .defaultSelection("DEFAULT")
                .build();
            
            Input input = Input.builder()
                .fileInput(inputS3Uri)
                .audioSelectors(Map.of("Audio Selector 1", audioSelector))
                .build();

            // Create HLS output settings
            HlsGroupSettings hlsGroupSettings = HlsGroupSettings.builder()
                .destination(outputS3Uri)
                .segmentLength(10) // 10 second segments
                .minSegmentLength(0)
                .build();

            // Create output settings
            OutputSettings outputSettings = OutputSettings.builder()
                .hlsSettings(HlsSettings.builder().build())
                .build();

            // Create container settings for HLS
            ContainerSettings containerSettings = ContainerSettings.builder()
                .container(ContainerType.M3_U8)
                .build();

            // Create video codec settings with 10 Mbps bitrate
            H264Settings h264Settings = H264Settings.builder()
                .bitrate(10000000) // 10 Mbps
                .codecLevel(H264CodecLevel.LEVEL_4_1)
                .codecProfile(H264CodecProfile.HIGH)
                .rateControlMode(H264RateControlMode.CBR)
                .build();

            VideoCodecSettings videoCodecSettings = VideoCodecSettings.builder()
                .codec(VideoCodec.H_264)
                .h264Settings(h264Settings)
                .build();

            // Create audio codec settings
            AacSettings aacSettings = AacSettings.builder()
                .bitrate(128000) // 128 kbps
                .codingMode(AacCodingMode.CODING_MODE_2_0)
                .sampleRate(48000)
                .build();

            AudioCodecSettings audioCodecSettings = AudioCodecSettings.builder()
                .codec(AudioCodec.AAC)
                .aacSettings(aacSettings)
                .build();

            // Create video description
            VideoDescription videoDescription = VideoDescription.builder()
                .codecSettings(videoCodecSettings)
                .build();

            // Create audio description
            AudioDescription audioDescription = AudioDescription.builder()
                .codecSettings(audioCodecSettings)
                .audioSourceName("Audio Selector 1")
                .build();

            // Create output
            Output output = Output.builder()
                .nameModifier("_hls")  // Fixed: nameModifier must be at least 1 character
                .outputSettings(outputSettings)
                .containerSettings(containerSettings)
                .videoDescription(videoDescription)
                .audioDescriptions(audioDescription)
                .build();

            // Create output group
            OutputGroup outputGroup = OutputGroup.builder()
                .name("HLS")
                .outputGroupSettings(OutputGroupSettings.builder()
                    .type(OutputGroupType.HLS_GROUP_SETTINGS)
                    .hlsGroupSettings(hlsGroupSettings)
                    .build())
                .outputs(output)
                .build();

            // Create job settings
            JobSettings jobSettings = JobSettings.builder()
                .inputs(input)
                .outputGroups(outputGroup)
                .build();

            // Create the job
            CreateJobRequest createJobRequest = CreateJobRequest.builder()
                .role(mediaConvertRoleArn)
                .settings(jobSettings)
                .userMetadata(Map.of(
                    "sourceKey", sourceObjectKey,
                    "isTrailer", String.valueOf(isTrailer)
                ))
                .build();

            CreateJobResponse response = clientWithEndpoint.createJob(createJobRequest);
            String jobId = response.job().id();
            
            logger.info("Successfully created MediaConvert job: jobId={}, input={}", jobId, inputS3Uri);
            return jobId;

        } finally {
            // Clean up the temporary client
            try {
                clientWithEndpoint.close();
            } catch (Exception e) {
                logger.warn("Failed to close MediaConvert client", e);
            }
        }
    }

    /**
     * Gets the status of a MediaConvert job.
     * 
     * @param jobId the job ID
     * @return the job details
     */
    public GetJobResponse getJob(String jobId) {
        try {
            GetJobRequest request = GetJobRequest.builder()
                .id(jobId)
                .build();
            return mediaConvertClient.getJob(request);
        } catch (Exception e) {
            logger.error("Failed to get MediaConvert job: {}", jobId, e);
            throw new RuntimeException("Failed to get MediaConvert job", e);
        }
    }
}
