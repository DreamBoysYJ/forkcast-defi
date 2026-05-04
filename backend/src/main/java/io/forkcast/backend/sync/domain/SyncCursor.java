package io.forkcast.backend.sync.domain;


import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "sync_cursor")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class SyncCursor {

  @Id
  @Column(name = "cursor_name", nullable = false, length = 100)
  private String cursorName;

  @Column(name = "last_synced_block", nullable = false)
  private long lastSyncedBlock;

  @Column(name="updated_at", nullable = false)
  private Instant updatedAt;

  public SyncCursor(String cursorName, long lastSyncedBlock) {
    this.cursorName = cursorName;
    this.lastSyncedBlock = lastSyncedBlock;
    this.updatedAt = Instant.now();
  }

  public void advanceTo(long lastSyncedBlock) {
    this.lastSyncedBlock = lastSyncedBlock;
    this.updatedAt = Instant.now();
  }
}
