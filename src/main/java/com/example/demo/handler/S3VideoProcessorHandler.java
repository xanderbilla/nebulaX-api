package com.example.demo.handler;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.S3Event;
import com.amazonaws.services.lambda.runtime.events.models.s3.S3EventNotification;
import com.example.demo.model.Video;
import com.example.demo.service.VideoService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;

import java.util.Arrays;
import java.util.List;

public class S3VideoProcessorHandler implements RequestHandler<S3Event, String> {

    private static final Logger logger = LoggerFactory.getLogger(S3VideoProcessorHandler.class);

    private static ConfigurableApplicationContext applicationContext;
    private static VideoService videoService;

    // Supported video file extensions
    private static final List<String> SUPPORTED_VIDEO_EXTENSIONS = Arrays.asList(
            ".mp4", ".avi", ".mov", ".mkv", ".wmv", ".flv", ".webm", ".m4v", ".3gp", ".ts");

    static {
        try {
            // Initialize Spring Boot application context
            System.setProperty("spring.profiles.active", "lambda");
            applicationContext = SpringApplication.run(com.example.demo.DemoApplication.class);
            videoService = applicationContext.getBean(VideoService.class);
            logger.info("Spring Boot application context initialized successfully");
        } catch (Exception e) {
            logger.error("Failed to initialize Spring Boot application context", e);
            throw new RuntimeException("Application initialization failed", e);
        }
    }

    @Override
    public String handleRequest(S3Event s3Event, Context context) {
        logger.info("Processing S3 event with {} records", s3Event.getRecords().size());

        int processedCount = 0;
        int skippedCount = 0;

        try {
            for (S3EventNotification.S3EventNotificationRecord record : s3Event.getRecords()) {
                String eventName = record.getEventName();
                S3EventNotification.S3Entity s3Entity = record.getS3();

                String bucketName = s3Entity.getBucket().getName();
                String objectKey = s3Entity.getObject().getUrlDecodedKey();

                logger.info("Processing S3 event: event={}, bucket={}, key={}", eventName, bucketName, objectKey);

                // Only process ObjectCreated events (PUT, POST, COPY, etc.)
                if (!eventName.startsWith("ObjectCreated")) {
                    logger.info("Skipping non-creation event: {}", eventName);
                    skippedCount++;
                    continue;
                }

                // Check if the file is a video file
                if (!isVideoFile(objectKey)) {
                    logger.info("Skipping non-video file: {}", objectKey);
                    skippedCount++;
                    continue;
                }

                try {
                    // Process the video upload
                    Video video = videoService.processVideoUpload(bucketName, objectKey);
                    logger.info("Successfully processed video: videoId={}, title={}",
                            video.getVideoId(), video.getTitle());
                    processedCount++;

                } catch (Exception e) {
                    logger.error("Failed to process video: bucket={}, key={}", bucketName, objectKey, e);
                    // Continue processing other files even if one fails
                }
            }

            String result = String.format("Processing completed: %d processed, %d skipped",
                    processedCount, skippedCount);
            logger.info(result);
            return result;

        } catch (Exception e) {
            logger.error("Error processing S3 event", e);
            throw new RuntimeException("S3 event processing failed", e);
        }
    }

    private boolean isVideoFile(String objectKey) {
        String lowerCaseKey = objectKey.toLowerCase();
        return SUPPORTED_VIDEO_EXTENSIONS.stream()
                .anyMatch(lowerCaseKey::endsWith);
    }

    // Optional: Cleanup method (though Lambda containers are ephemeral)
    public static void shutdown() {
        if (applicationContext != null) {
            applicationContext.close();
        }
    }
}
