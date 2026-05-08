package io.forkcast.backend.sync.repository;

import io.forkcast.backend.sync.domain.SyncCursor;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SyncCursorRepository extends JpaRepository<SyncCursor, String> {
}
