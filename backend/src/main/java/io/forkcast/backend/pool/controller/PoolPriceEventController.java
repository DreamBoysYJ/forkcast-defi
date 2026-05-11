package io.forkcast.backend.pool.controller;


import io.forkcast.backend.pool.dto.PoolPriceEventResponse;
import io.forkcast.backend.pool.service.PoolPriceEventQueryService;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/pools")
public class PoolPriceEventController {

  private final PoolPriceEventQueryService poolPriceEventQueryService;

  public PoolPriceEventController(PoolPriceEventQueryService poolPriceEventQueryService) {
    this.poolPriceEventQueryService = poolPriceEventQueryService;
  }

  @GetMapping("/{poolId}/price-events")
  public Map<String, Object> getPriceEvents(
    @PathVariable String poolId,
    @RequestParam(defaultValue = "20") int limit
  ){
    List<PoolPriceEventResponse> items = poolPriceEventQueryService.getPriceEvents(poolId, limit);

    Map<String, Object> response = new LinkedHashMap<>();
    response.put("items", items);
    response.put("nextCursor", null);
    return response;
  }
}
