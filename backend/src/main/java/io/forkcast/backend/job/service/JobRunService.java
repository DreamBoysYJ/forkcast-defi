package io.forkcast.backend.job.service;


import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.repository.JobRunRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class JobRunService {

  private final JobRunRepository jobRunRepository;

  public JobRunService(JobRunRepository jobRunRepository) {
    this.jobRunRepository = jobRunRepository;
  }


  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public JobRun start(String jobName, Long rangeStartBlock, Long rangeEndBlock) {
    JobRun jobRun = JobRun.start(jobName, rangeStartBlock, rangeEndBlock);
    return jobRunRepository.save(jobRun);
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public JobRun markFailed(Long jobRunId, String errorMessage) {
    JobRun jobRun = getOrThrow(jobRunId);
    jobRun.markFailed(errorMessage);
    return jobRun;
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public JobRun markSuccess(Long jobRunId) {
    JobRun jobRun = getOrThrow(jobRunId);
    jobRun.markSuccess();
    return jobRun;
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public JobRun markSkipped(Long jobRunId) {
    JobRun jobRun = getOrThrow(jobRunId);
    jobRun.markSkipped();
    return jobRun;
  }




  @Transactional(readOnly = true)
  public JobRun getOrThrow(Long jobRunId) {
    return jobRunRepository.findById(jobRunId)
      .orElseThrow(() -> new IllegalArgumentException("job run not found : " + jobRunId));
  }
}
