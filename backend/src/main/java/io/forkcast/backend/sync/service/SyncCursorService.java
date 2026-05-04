package io.forkcast.backend.sync.service;


import io.forkcast.backend.sync.domain.SyncCursor;
import io.forkcast.backend.sync.repository.SyncCursorRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Transactional
@Service
public class SyncCursorService {

  private final SyncCursorRepository syncCursorRepository;

  public SyncCursorService(SyncCursorRepository syncCursorRepository) {
    this.syncCursorRepository = syncCursorRepository;
  }

  @Transactional(readOnly = true)
  public SyncCursor getOrThrow(String cursorName) {
    return syncCursorRepository.findById(cursorName)
      .orElseThrow(() -> new IllegalArgumentException("Sync Cursor not found: " + cursorName));
  }

  public SyncCursor getOrCreate(String cursorName, long initialBlock) {
    return syncCursorRepository.findById(cursorName)
      .orElseGet(() -> syncCursorRepository.save(new SyncCursor(cursorName, initialBlock)));
  }

  public SyncCursor advance(String cursorName, long newLasSyncedBlock) {
    SyncCursor cursor = getOrThrow(cursorName);
    cursor.advanceTo(newLasSyncedBlock);
    return cursor;
  }


}
