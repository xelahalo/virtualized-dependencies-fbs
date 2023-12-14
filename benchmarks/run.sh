#!/bin/sh

COMMIT_HASH=$(git log -1 --pretty=%h)
BENCHMARK_NAME=$(date +%Y-%m-%d_%H-%M-%S)_$COMMIT_HASH

# for each directory in stage_1
for d in benchmarks/commands/*; do
	EXECUTABLE=$(basename $d)

	# for each dir for the executable
	for f in $d/*; do
		# if it is a directory 
		if [ -d "$f" ] ; then
      echo "-----------------------------------------"
      echo "Benchmarking $f"
      echo "-----------------------------------------"

			# copy the benchmark test to the workdir
			rsync -av $f/ host_mnt/workdir/

			if [ "$EXECUTABLE" = "stress" ]; then
        cp $d/gcc host_mnt/workdir/
      else
		  	cp $d/$EXECUTABLE host_mnt/workdir/
      fi

			cd host_mnt/workdir/ || exit
			chmod +x run.sh

			# STEP 1: Benchmark it locally
			# if [ "$EXECUTABLE" = "stress" ]; then
   #      hyperfine --warmup 3 --parameter-scan iter 1 11 -D 2 './run.sh {iter}' --export-json local_$BENCHMARK_NAME.json
   #    else
   #    	hyperfine --warmup 3 './run.sh' --export-json local_$BENCHMARK_NAME.json
   #    fi 


			# STEP 2: Benchmark it in docker
      # docker exec build-env mkdir -p /usr/src/benchmark/
      # docker exec build-env rsync -av /usr/src/dockermount/workdir/ /usr/src/benchmark/
      # 
      # docker exec build-env /bin/bash -c "cd /usr/src/benchmark && chmod +x run.sh && \
      # if [ \"$EXECUTABLE\" = \"stress\" ]; then \
      #   hyperfine --warmup 3 --parameter-scan iter 1 101 -D 10 './run.sh {iter}' --export-json docker_$BENCHMARK_NAME.json; \
      # else \
      #   hyperfine --warmup 3 './run.sh' --export-json docker_$BENCHMARK_NAME.json; \
      # fi"
      #
      # docker exec build-env cp /usr/src/benchmark/docker_$BENCHMARK_NAME.json /usr/src/dockermount/workdir/
      # docker exec build-env find /usr/src/benchmark -delete

      # STEP 3: Benchmark it in docker on top of FUSE
      docker exec build-env mkdir -p /usr/src/fuse_benchmark/ 
      docker exec build-env /bin/bash -c "gcc -Wall libfuse_examples/passthrough_ll.c \`pkg-config fuse3 --cflags --libs\` -o passthrough_ll"
      docker exec build-env ./passthrough_ll /usr/src/fuse_benchmark 
      docker exec build-env mkdir -p /usr/src/fuse_benchmark/workdir 
      docker exec build-env /bin/bash -c "rsync -av /usr/src/dockermount/workdir/ /usr/src/fuse_benchmark/workdir/"
      docker exec build-env /bin/bash -c "cd /usr/src/fuse_benchmark/workdir && chmod +x run.sh && \
        if [ \"$EXECUTABLE\" = \"stress\" ]; then \
          hyperfine --warmup 3 --parameter-scan iter 1 11 -D 2 './run.sh {iter}' --export-json fuse_docker_$BENCHMARK_NAME.json; \
        else \
          hyperfine --warmup 3 './run.sh' --export-json fuse_docker_$BENCHMARK_NAME.json; \
        fi"
      docker exec build-env cp /usr/src/fuse_benchmark/workdir/fuse_docker_$BENCHMARK_NAME.json /usr/src/dockermount/workdir/ 
      docker exec build-env find /usr/src/fuse_benchmark/workdir -delete 
      docker exec build-env umount /usr/src/fuse_benchmark


			# STEP 4: Benchmark it using Cairn
			if [ "$EXECUTABLE" = "stress" ]; then
        hyperfine --warmup 3 --parameter-scan iter 1 11 -D 2 'cairn "./run.sh {iter}" --container build-env' --export-json cairn_$BENCHMARK_NAME.json
      else
      	hyperfine --warmup 3 'cairn "./run.sh" --container build-env' --export-json cairn_$BENCHMARK_NAME.json
      fi

			cd ../..

			# move the json to the benchmark directory
			mkdir -p benchmarks/results/$EXECUTABLE/$(basename $f)
			# copy over all the files that were used to make the benchmarks
			rsync -avhr --exclude ".gitkeep" host_mnt/workdir/* benchmarks/results/$EXECUTABLE/$(basename $f)

			# clean up workdir
			find host_mnt/workdir \( -type d -o -type f \) ! -name ".gitkeep" -mindepth 1 -exec rm -r {} \;
		fi
	done
done

# run python scripts
source venv/bin/activate
python3 benchmarks/tex.py benchmarks/results/
python3 benchmarks/plot.py benchmarks/results/stress
deactivate

# # zip the results
cd benchmarks/results
zip -r $BENCHMARK_NAME.zip *
cd ../..
mv benchmarks/results/$BENCHMARK_NAME.zip benchmarks/
rm -rf benchmarks/results/

