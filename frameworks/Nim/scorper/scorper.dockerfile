FROM nimlang/nim:alpine

ENV PATH $PATH:/root/.nimble/bin

ADD ./ /scorper
WORKDIR /scorper

RUN nimble install -d -y
RUN nimble c -d:TestWhileIdle=false -d:GzipEnable=false -d:ResetConnection=false -d:ChronosAsync -d:timeout=30000 -d:release -o:scorper_bench_bin ./scorper_bench.nim

EXPOSE 8080

CMD ./scorper_bench_bin
