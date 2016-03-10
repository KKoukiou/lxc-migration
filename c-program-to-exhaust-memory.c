#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define PAGE_SZ (1<<12)

int main() {
	int i;
	int gb = 1; // memory to consume in GB
	int mb = 250; //memory to consume in MB
	void *m = malloc((unsigned long)mb<<20);
	if (!m)
		return 0;
	time_t endwait;
    	time_t start = time(NULL);
    	time_t seconds = 60; // after 60s, end loop.
	endwait = start + seconds;
	while(start < endwait){
		for (i = 0; i < ((unsigned long)mb<<20)/PAGE_SZ ; ++i) {
			memset(m+i*PAGE_SZ, 10, 1);
		}
		start = time(NULL);
	}
	return 0;
}


