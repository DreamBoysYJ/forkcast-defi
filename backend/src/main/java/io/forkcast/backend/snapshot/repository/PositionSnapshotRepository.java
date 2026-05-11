package io.forkcast.backend.snapshot.repository;

import io.forkcast.backend.snapshot.domain.PositionSnapshot;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;

public interface PositionSnapshotRepository extends JpaRepository<PositionSnapshot, Long> {
  boolean existsByTokenIdAndSnapshotAt(Long tokenId, Instant snapshotAt);

  List<PositionSnapshot> findByTokenIdOrderBySnapshotAtDesc(Long tokenId, Pageable pageable);
}
