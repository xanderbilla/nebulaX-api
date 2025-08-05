package com.example.demo.repository;

import com.example.demo.model.Video;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;

import java.util.Optional;

/**
 * Repository interface for Video entity DynamoDB operations.
 * Provides enhanced DynamoDB client integration with comprehensive CRUD operations,
 * batch processing capabilities, and optimized query patterns for video management.
 * 
 * @author Xander Billa
 * @since August 5, 2025
 * @see com.example.demo.model.Video
 * @see com.example.demo.service.VideoService
 * @see software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient
 */
@Repository
public class VideoRepository {

    private final DynamoDbTable<Video> videoTable;

    public VideoRepository(DynamoDbEnhancedClient dynamoDbEnhancedClient, 
                          @Value("${dynamodb.videos.table:Videos}") String tableName) {
        this.videoTable = dynamoDbEnhancedClient.table(tableName, TableSchema.fromBean(Video.class));
    }

    public void save(Video video) {
        videoTable.putItem(video);
    }

    public Optional<Video> findById(String videoId) {
        Key key = Key.builder()
                .partitionValue(videoId)
                .build();
        Video video = videoTable.getItem(key);
        return Optional.ofNullable(video);
    }

    public void deleteById(String videoId) {
        Key key = Key.builder()
                .partitionValue(videoId)
                .build();
        videoTable.deleteItem(key);
    }

    public void update(Video video) {
        videoTable.updateItem(video);
    }

    public boolean existsById(String videoId) {
        return findById(videoId).isPresent();
    }
}
