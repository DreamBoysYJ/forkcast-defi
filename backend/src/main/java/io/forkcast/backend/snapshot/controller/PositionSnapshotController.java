package io.forkcast.backend.snapshot.controller;

import io.forkcast.backend.snapshot.dto.PositionSnapshotResponse;
import io.forkcast.backend.snapshot.service.PositionSnapshotQueryService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/positions")
public class PositionSnapshotController {

  private final PositionSnapshotQueryService positionSnapshotQueryService;

  public PositionSnapshotController(PositionSnapshotQueryService positionSnapshotQueryService) {
    this.positionSnapshotQueryService = positionSnapshotQueryService;
  }

  @GetMapping("/{tokenId}/snapshots")
  public Map<String, Object> getSnapshots(
    @PathVariable Long tokenId,
    @RequestParam(defaultValue = "20") int limit
  ) {
    List<PositionSnapshotResponse> items = positionSnapshotQueryService.getSnapshots(tokenId, limit);

    Map<String, Object> response = new LinkedHashMap<>();
    response.put("items", items);
    response.put("nextCursor", null);
    return response;
  }
}
