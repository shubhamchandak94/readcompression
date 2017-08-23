#!/bin/bash
set -e
# Download data
# DATA_DIR="data/"

#################
# PARAMETERS
#################
reorder_thresh=4
denoise_thresh=0.0





usage()
{
cat << EOF

HARC compression tool for genomic reads. Works on fixed length reads of length less than 256.

Usage: 
Compression - compresses FASTQ reads. Output written to .tar file
./run_default.sh -c PATH_TO_FASTQ [-p] [-t NUM_THREADS] [-q]
-p Preserve order of reads
-t NUM_THREADS - Default 8
-q Write quality values to .quality file. Quality values are appropriately reordered if -p is not specified. 

Decompression - decompresses reads. Output written to .dna.d file
./run_default.sh -d PATH_TO_TAR [-p] [-t NUM_THREADS] [-m max_memory]
-p Get reads in original order (slower). Only applicable if -p was used during compression.
-t NUM_THREADS - Default 8
-m max_memory - Controls memory-time tradeoff for decompression with -p. Specify max memory in GB (minimum 3 GB). e.g. -m 10 for 10 GB maximum memory. Default: 7 GB (note: less than 3 GB memory required if -p not specified)

Help (this message)
./run_default.sh -h

EOF
exit 0
}

compress()
{
	pathname=$(dirname $filename)
	echo "*** Preprocessing ***"
	echo $filename
	if [[ $preserve_quality == "True" ]];then
		./src/preprocess_quality.out $filename $pathname $num_thr
	else
		./src/preprocess.out $filename $pathname $num_thr
	fi
	readlen="$(head $pathname/input_clean.dna | wc -L)"
	if (($readlen > 256));then
		echo "Maximum read length exceeded" 
		exit 1
	fi
	echo "#define maxmatch $((readlen/2))" > src/config.h

	echo "#define thresh $reorder_thresh" >> src/config.h

	echo "#define thresh_s 24" >> src/config.h
	echo "#define numdict 2" >> src/config.h
	echo "#define maxsearch 1000" >> src/config.h
	echo "#define dict1_start $(( readlen > 100 ? readlen/2-32 : readlen/2-readlen*32/100 ))" >> src/config.h
	echo "#define dict1_end $((readlen/2-1))" >> src/config.h
	echo "#define dict2_start $((readlen/2))" >> src/config.h
	echo "#define dict2_end $(( readlen > 100 ? readlen/2-1+32 : readlen/2-1+readlen*32/100 ))" >> src/config.h

	echo "#define readlen $readlen" >> src/config.h
	echo "#define num_thr $num_thr" >> src/config.h

	g++ src/reorder.cpp -w -march=native -O3 -fopenmp -lpthread -std=c++11 -o src/reorder.out
	mkdir -p $pathname/output/
	 
	./src/reorder.out $pathname
	mv $pathname/input_N.dna $pathname/output/input_N.dna
	mv $pathname/input_clean.dna $pathname/output/input_clean.dna
	mv $pathname/read_order_N.bin $pathname/output/read_order_N.bin
	if [[ $preserve_quality == "True" ]];then
		mv $pathname/input_N.quality $pathname/output/input_N.quality
		mv $pathname/input_clean.quality $pathname/output/input_clean.quality
	fi

	g++ src/encoder.cpp -w -march=native -O3 -fopenmp -lpthread -std=c++11 -o src/encoder.out
	./src/encoder.out $pathname $denoise_thresh
	
	#remove temporary files
	rm $pathname/output/temp.dna
	#rm $pathname/output/tempflag.txt
	rm $pathname/output/temppos.txt
	rm $pathname/output/read_rev.txt
	
	#tar files produced by the threads
	mkdir -p $pathname/output/read_noise
	mv $pathname/output/read_noise.txt* $pathname/output/read_noise
	mkdir -p $pathname/output/read_noisepos
	mv $pathname/output/read_noisepos.txt* $pathname/output/read_noisepos
	mkdir -p $pathname/output/read_pos
	mv $pathname/output/read_pos.txt* $pathname/output/read_pos
	mkdir -p $pathname/output/read_seq
	mv $pathname/output/read_seq.txt* $pathname/output/read_seq
	mkdir -p $pathname/output/read_rev
	mv $pathname/output/read_rev.txt* $pathname/output/read_rev

	tar -cf	$pathname/output/read_noise.tar -C $pathname/output/read_noise .
	tar -cf	$pathname/output/read_noisepos.tar -C $pathname/output/read_noisepos .
	tar -cf	$pathname/output/read_pos.tar -C $pathname/output/read_pos .
	tar -cf	$pathname/output/read_seq.tar -C $pathname/output/read_seq .
	tar -cf	$pathname/output/read_rev.tar -C $pathname/output/read_rev .
	
	rm -r $pathname/output/read_noise
	rm -r $pathname/output/read_noisepos
	rm -r $pathname/output/read_pos
	rm -r $pathname/output/read_seq
	rm -r $pathname/output/read_rev
	
	#compress and create tarball

	./src/libbsc/bsc e $pathname/output/read_pos.tar $pathname/output/read_pos.tar.bsc -b64p -t$num_thr
	./src/libbsc/bsc e $pathname/output/read_noise.tar $pathname/output/read_noise.tar.bsc -b64p -t$num_thr
	7z a $pathname/output/tempflag.txt.7z $pathname/output/tempflag.txt -mmt=$num_thr
	7z a $pathname/output/read_noisepos.tar.7z $pathname/output/read_noisepos.tar -mmt=$numt_thr
	./src/libbsc/bsc e $pathname/output/input_N.dna $pathname/output/input_N.dna.bsc -b64p -t$num_thr

	7z a $pathname/output/read_meta.txt.7z $pathname/output/read_meta.txt -mmt=$numt_thr
	7z a $pathname/output/read_rev.tar.7z $pathname/output/read_rev.tar -mmt=$num_thr
	./src/libbsc/bsc e $pathname/output/read_seq.tar $pathname/output/read_seq.tar.bsc -b64p -t$num_thr 
	./src/libbsc/bsc e $pathname/output/read_singleton.txt $pathname/output/read_singleton.txt.bsc -b64p -t$num_thr 
	rm $pathname/output/*.txt $pathname/output/*.dna $pathname/output/*.tar 
	if [[ $preserve_order == "True" ]];then
		./src/pack_order.out $pathname	
		7z a $pathname/output/read_order.bin.7z $pathname/output/read_order.bin -mmt=$num_thr
		7z a $pathname/output/read_order_N.bin.7z $pathname/output/read_order_N.bin -mmt=$num_thr
		7z a $pathname/output/read_order_N_pe.bin.7z $pathname/output/read_order_N_pe.bin -mmt=$num_thr ########KEDAR
		if [[ $preserve_quality == "True" ]];then
			./src/merge_quality_N.out $pathname
			mv $pathname/output/output.quality $pathname/$(basename "$filename" .fastq).quality
			mv $pathname/output.readid $pathname/$(basename "$filename" .fastq).readid
			rm $pathname/output/*.quality
		fi
	else
		if [[ $preserve_quality == "True" ]];then
			echo "Reordering quality values"
			g++ src/reorder_quality.cpp -march=native -O3 -std=c++11 -o src/reorder_quality.out
			./src/reorder_quality.out $pathname
			mv $pathname/output/output.quality $pathname/$(basename "$filename" .fastq).quality
			rm $pathname/output/*.quality
			echo "Done!"
		fi	
	fi
	rm $pathname/output/*.bin
	rm $pathname/output/*.singleton
	tar -cf $pathname/$(basename "$filename" .fastq).tar -C $pathname/output .
	rm -r $pathname/output/
}

decompress()
{
	echo "Decompression ..."
	pathname=$(dirname $filename)
	mkdir -p $pathname/output
	tar -xf $filename -C $pathname/output
	if [[ $preserve_order == "True" ]];then
		if [ ! -f $pathname/output/read_order.bin.7z ];then
			echo "Not compressed using -p flag. Order cannot be restored"
			usage
			exit 1
		fi
	fi

	./src/libbsc/bsc d $pathname/output/read_pos.tar.bsc $pathname/output/read_pos.tar -t$num_thr
	./src/libbsc/bsc d $pathname/output/read_noise.tar.bsc $pathname/output/read_noise.tar -t$num_thr
	7z e $pathname/output/tempflag.txt.7z -o$pathname/output/
	7z e $pathname/output/read_noisepos.tar.7z -o$pathname/output/
	./src/libbsc/bsc d $pathname/output/input_N.dna.bsc $pathname/output/input_N.dna -t$num_thr
	7z e $pathname/output/read_meta.txt.7z -o$pathname/output/
	7z e $pathname/output/read_rev.tar.7z -o$pathname/output/
	./src/libbsc/bsc d $pathname/output/read_seq.tar.bsc $pathname/output/read_seq.tar -t$num_thr
	./src/libbsc/bsc d $pathname/output/read_singleton.txt.bsc $pathname/output/read_singleton.txt -t$num_thr
	
	
	tar -xf $pathname/output/read_pos.tar -C $pathname/output/
	tar -xf $pathname/output/read_noisepos.tar -C $pathname/output/
	tar -xf $pathname/output/read_noise.tar -C $pathname/output/
	tar -xf $pathname/output/read_rev.tar -C $pathname/output/
	tar -xf $pathname/output/read_seq.tar -C $pathname/output/
	
	num_thr_e=$(ls $pathname/output/read_pos.txt* | wc -l) #number of encoding threads
			
	if [[ $preserve_order == "True" ]];then
		readlen=$( cat $pathname/output/read_meta.txt )
		echo "#define readlen $readlen" > src/config.h
		echo "#define MAX_BIN_SIZE $memory" >> src/config.h
		echo "#define num_thr $num_thr" >> src/config.h
		echo "#define num_thr_e $num_thr_e" >> src/config.h
		g++ src/decoder_preserve.cpp -O3 -march=native -fopenmp -std=c++11 -o src/decoder_preserve.out
		7z e $pathname/output/read_order.bin.7z -o$pathname/output/
		7z e $pathname/output/read_order_N.bin.7z -o$pathname/output/
		7z e $pathname/output/read_order_N_pe.bin.7z -o$pathname/output/
		./src/unpack_order.out $pathname
		./src/decoder_preserve.out $pathname
		./src/merge_N.out $pathname
		echo "Done!"
	else
		./src/decoder.out $pathname $num_thr $num_thr_e
	fi

	#rm -r $pathname/output/
	mv $pathname/output/output.dna $pathname/$(basename "$filename" .tar).dna.d
	rm -r $pathname/output/
	#mv $pathname/output.dna $pathname/output/output.dna
}

#Initialize variables to default values.
num_thr=8

#Check the number of arguments. If none are passed, print help and exit.
NUMARGS=$#
if [ $NUMARGS -eq 0 ]; then
 usage
fi

mode=''
preserve_order="False"
preserve_quality="False"
memory='7'

while getopts ':c:d:t:m:n:pqh' opt; do
  case "$opt" in
    c) [[ -n "$mode" ]] && usage || mode='c' && filename=$OPTARG;;
    d) [[ -n "$mode" ]] && usage || mode='d' && filename=$OPTARG;;
    t) num_thr=$OPTARG;;
    m) memory=$OPTARG;;
    p) preserve_order="True";;
    q) preserve_quality="True";;
    n) denoise_thresh=$OPTARG;;	
    h) usage ;;
    \?) usage ;;
    *) usage ;;
  esac
done

if [[ $mode == 'c' ]];then
compress
elif [[ $mode == 'd' ]];then
decompress
else
echo "Either -c or -d required"
usage
exit 1
fi;
