package io.forkcast.backend.position.service;


import io.forkcast.backend.position.dto.PositionTimelineResponse;
import io.forkcast.backend.position.repository.PositionTimelineRepository;
import io.forkcast.backend.snapshot.repository.PositionSnapshotRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(readOnly = true)
public class PositionTimelineQueryService {

  private final PositionTimelineRepository positionTimelineRepository;

  public PositionTimelineQueryService(PositionTimelineRepository positionTimelineRepository) {
    this.positionTimelineRepository = positionTimelineRepository;
  }

  public List<PositionTimelineResponse> getTimeline(Long tokenId, int limit) {
    return positionTimelineRepository.findByTokenIdOrderByEventTimestampDesc(
      tokenId,
      PageRequest.of(0,limit)
    ).stream().map(PositionTimelineResponse::from).toList();

  }
}
