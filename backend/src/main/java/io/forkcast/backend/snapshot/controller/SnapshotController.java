package io.forkcast.backend.snapshot.controller;

import io.forkcast.backend.snapshot.service.SnapshotService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/internal/jobs")
public class SnapshotController {

  private final SnapshotService snapshotService;

  public SnapshotController(SnapshotService snapshotService) {
    this.snapshotService = snapshotService;
  }

  @PostMapping("/snapshot")
  public ResponseEntity<SnapshotService.SnapshotResult> runSnapshot() {
    SnapshotService.SnapshotResult result = snapshotService.run();

    if ("SKIPPED".equals(result.status())) {
      return ResponseEntity.status(HttpStatus.ACCEPTED).body(result);
    }

    return ResponseEntity.ok(result);
  }
}
