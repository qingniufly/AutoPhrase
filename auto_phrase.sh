FIRST_RUN=1
RAW_TRAIN=data/DBLP.txt
ENABLE_POS_TAGGING=1
THREAD=10
LABEL_METHOD=ByRandom
MAX_POSITIVES=100
NEGATIVE_RATIO=7

green=`tput setaf 2`
reset=`tput sgr0`

echo ${green}===Compilation===${reset}

if [ "$(uname)" == "Darwin" ]; then
	make all CXX=g++-6 | grep -v "Nothing to be done for"
	cp tools/treetagger/bin/tree-tagger-mac tools/treetagger/bin/tree-tagger
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
        make all CXX=g++ | grep -v "Nothing to be done for"
	if [[ $(uname -r) == 2.6* ]]; then
		cp tools/treetagger/bin/tree-tagger-linux-old tools/treetagger/bin/tree-tagger
	else
		cp tools/treetagger/bin/tree-tagger-linux tools/treetagger/bin/tree-tagger
	fi
fi
if [ ! -e tools/tokenizer/build/Tokenizer.class ]; then
    mkdir -p tools/tokenizer/build/
	javac -cp ".:tools/tokenizer/lib/*" tools/tokenizer/src/Tokenizer.java -d tools/tokenizer/build/
fi

mkdir -p tmp
mkdir -p results

if [ $RAW_TRAIN == "data/DBLP.txt" ] && [ ! -e data/DBLP.txt ]; then
    echo ${green}===Downloading dataset===${reset}
    curl http://dmserv2.cs.illinois.edu/data/DBLP.txt.gz --output data/DBLP.txt.gz
    gzip -d data/DBLP.txt.gz -f
fi

### END Compilation###

echo ${green}===Tokenization===${reset}

TOKENIZER="-cp .:tools/tokenizer/lib/*:tools/tokenizer/resources/:tools/tokenizer/build/ Tokenizer"
TOKENIZED_TRAIN=tmp/tokenized_train.txt
CASE=tmp/case_tokenized_train.txt
TOKEN_MAPPING=tmp/token_mapping.txt

if [ $FIRST_RUN -eq 1 ]; then
    echo -ne "Current step: Tokenizing input file...\033[0K\r"
    time java $TOKENIZER -m train -i $RAW_TRAIN -o $TOKENIZED_TRAIN -t $TOKEN_MAPPING -c N -thread $THREAD
fi
LANGUAGE=`cat tmp/language.txt`
echo -ne "Detected Language: $LANGUAGE\033[0K\n"
TOKENIZED_STOPWORDS=tmp/tokenized_stopwords.txt
TOKENIZED_ALL=tmp/tokenized_all.txt
TOKENIZED_QUALITY=tmp/tokenized_quality.txt
STOPWORDS=data/$LANGUAGE/stopwords.txt
ALL_WIKI_ENTITIES=data/$LANGUAGE/wiki_all.txt
QUALITY_WIKI_ENTITIES=data/$LANGUAGE/wiki_quality.txt
if [ $FIRST_RUN -eq 1 ]; then
    echo -ne "Current step: Tokenizing stopword file...\033[0K\r"
	java $TOKENIZER -m test -i $STOPWORDS -o $TOKENIZED_STOPWORDS -t $TOKEN_MAPPING -c N -thread $THREAD
	echo -ne "Current step: Tokenizing wikipedia phrases...\033[0K\n"
	java $TOKENIZER -m test -i $ALL_WIKI_ENTITIES -o $TOKENIZED_ALL -t $TOKEN_MAPPING -c N -thread $THREAD
	java $TOKENIZER -m test -i $QUALITY_WIKI_ENTITIES -o $TOKENIZED_QUALITY -t $TOKEN_MAPPING -c N -thread $THREAD
fi	
### END Tokenization ###

echo ${green}===Part-Of-Speech Tagging===${reset}

if [ ! $LANGUAGE == "JA" ] && [ ! $LANGUAGE == "CN" ]  && [ $ENABLE_POS_TAGGING -eq 1 ] && [ $FIRST_RUN -eq 1 ]; then
	RAW=tmp/raw_tokenized_train.txt
	export THREAD LANGUAGE RAW
	bash ./tools/treetagger/pos_tag.sh
    mv tmp/pos_tags.txt tmp/pos_tags_tokenized_train.txt
fi

### END Part-Of-Speech Tagging ###

echo ${green}===Segphrasing===${reset}

if [ $ENABLE_POS_TAGGING -eq 1 ]; then
	time ./bin/segphrase_train \
        --verbose \
        --pos_tag \
        --thread $THREAD \
        --pos_prune data/BAD_POS_TAGS.txt \
        --label_method $LABEL_METHOD \
        --max_positives $MAX_POSITIVES \
        --negative_ratio $NEGATIVE_RATIO
else
	time ./bin/segphrase_train \
        --verbose \
        --thread $THREAD \
        --label_method $LABEL_METHOD \
        --max_positives $MAX_POSITIVES \
        --negative_ratio $NEGATIVE_RATIO
fi

### END Segphrasing ###

echo ${green}===Generating Output===${reset}
java $TOKENIZER -m translate -i tmp/final_quality_multi-words.txt -o results/AutoPhrase_multi-words.txt -t $TOKEN_MAPPING -c N -thread $THREAD
java $TOKENIZER -m translate -i tmp/final_quality_unigrams.txt -o results/AutoPhrase_single-word.txt -t $TOKEN_MAPPING -c N -thread $THREAD
java $TOKENIZER -m translate -i tmp/final_quality_salient.txt -o results/AutoPhrase.txt -t $TOKEN_MAPPING -c N -thread $THREAD

### END Generating Output for Checking Quality ###