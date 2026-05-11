package io.forkcast.backend.sync.controller;


import io.forkcast.backend.sync.service.EventSyncService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/internal/jobs")
public class EventSyncController {

  private final EventSyncService eventSyncService;

  public EventSyncController(EventSyncService eventSyncService) {
    this.eventSyncService = eventSyncService;
  }

  @PostMapping("/event-sync")
  public ResponseEntity<EventSyncService.EventSyncResult> runEventSync() {
    EventSyncService.EventSyncResult result = eventSyncService.run();

    if ("SKIPPED".equals(result.status())) {
      return ResponseEntity.status(HttpStatus.ACCEPTED).body(result);
    }

    return ResponseEntity.ok(result);
  }
}
