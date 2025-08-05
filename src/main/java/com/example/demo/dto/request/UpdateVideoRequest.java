package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UpdateVideoRequest {

    @Size(min = 1, max = 255, message = "Title must be between 1 and 255 characters")
    private String title;

    @Pattern(regexp = "^(video|trailer|poster)$", message = "Type must be one of: video, trailer, poster")
    private String type;

    @Pattern(regexp = "^(tv|movie|live)$", message = "Category must be one of: tv, movie, live")
    private String category;

    private String posterUrl;
    private String trailerUrl;
}
