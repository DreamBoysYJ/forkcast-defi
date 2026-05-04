package io.forkcast.backend.position.controller;


import io.forkcast.backend.position.dto.PositionTimelineResponse;
import io.forkcast.backend.position.service.PositionTimelineQueryService;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/positions")
public class PositionTimelineController {

  private final PositionTimelineQueryService positionTimelineQueryService;

  public PositionTimelineController(PositionTimelineQueryService positionTimelineQueryService) {
    this.positionTimelineQueryService = positionTimelineQueryService;
  }

  @GetMapping("/{tokenId}/timeline")
  public Map<String, Object> getTimeline(
    @PathVariable Long tokenId,
    @RequestParam(defaultValue = "20") int limit
  ){
    List<PositionTimelineResponse> items = positionTimelineQueryService.getTimeline(tokenId, limit);

    Map<String, Object> response = new LinkedHashMap<>();
    response.put("items", items);
    response.put("nextCursor", null);
    return response;
  }

}
