package io.forkcast.backend.position.controller;


import io.forkcast.backend.position.dto.OpenPositionResponse;
import io.forkcast.backend.position.service.OpenPositionQueryService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
public class OpenPositionController {


  private final OpenPositionQueryService openPositionQueryService;

  public OpenPositionController(OpenPositionQueryService openPositionQueryService) {
    this.openPositionQueryService = openPositionQueryService;
  }

  @GetMapping("/api/users/{userAddress}/positions/open")
  public Map<String, Object> getUserOpenPositions(
    @PathVariable String userAddress,
    @RequestParam(defaultValue = "20") int limit
  ){
    List<OpenPositionResponse> items = openPositionQueryService.getOpenPositionsByUser(userAddress, limit);
    Map<String, Object> response = new LinkedHashMap<>();
    response.put("items", items);
    response.put("nextCursor", null);
    return response;
  }
    @GetMapping("/api/positions/open")
  public Map<String, Object> getOpenPositions(
    @RequestParam(defaultValue = "20") int limit
  ){
    List<OpenPositionResponse> items = openPositionQueryService.getOpenPositions(limit);
    Map<String, Object> response = new LinkedHashMap<>();
    response.put("items", items);
    response.put("nextCursor", null);
    return response;
  }


}
