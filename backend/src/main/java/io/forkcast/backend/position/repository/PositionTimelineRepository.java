package io.forkcast.backend.position.repository;

import io.forkcast.backend.position.domain.PositionTimeline;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PositionTimelineRepository extends JpaRepository<PositionTimeline, Long> {

  List<PositionTimeline> findByTokenIdOrderByEventTimestampDesc(
    Long tokenId,
    Pageable pageable
  );
}
