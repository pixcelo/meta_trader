class LocalExtremaSeeker
{
private:
    struct Point {
        double value;
        datetime timestamp;
        bool isPeak;
    };

    Point points[];
    int depth;

public:
    LocalExtremaSeeker(int d=7) {
        depth = d;
    }

    // Peakを見つける
    void findPeaks(double &prices[], datetime &times[]) {
        ArrayResize(points, 0);  // ピークや谷を探す前に配列をクリア
        int lastPeakIndex = -depth;  // 最後に見つかったピークのインデックス

        for (int i = depth; i < ArraySize(prices) - depth; i++) {
            bool isPeak = true;
            for (int j = 1; j <= depth; j++) {
                if (prices[i] <= prices[i-j] || prices[i] <= prices[i+j]) {
                    isPeak = false;
                    break;
                }
            }

            if (isPeak && (i - lastPeakIndex) >= depth) {
                Point pt;
                pt.value = prices[i];
                pt.timestamp = times[i];
                pt.isPeak = true;
                
                int newSize = ArraySize(points) + 1;
                ArrayResize(points, newSize);
                points[newSize - 1] = pt;

                lastPeakIndex = i;  // ピークのインデックスを更新
            }
        }
    }

    // Valleyを見つける
    void findValleys(double &prices[], datetime &times[]) {
        ArrayResize(points, 0);  // ピークや谷を探す前に配列をクリア
        int lastValleyIndex = -depth;  // 最後に見つかった谷のインデックス

        for (int i = depth; i < ArraySize(prices) - depth; i++) {
            bool isValley = true;
            for (int j = 1; j <= depth; j++) {
                if (prices[i] >= prices[i-j] || prices[i] >= prices[i+j]) {
                    isValley = false;
                    break;
                }
            }
            
            if (isValley && (i - lastValleyIndex) >= depth) {
                Point pt;
                pt.value = prices[i];
                pt.timestamp = times[i];
                pt.isPeak = false;
                
                int newSize = ArraySize(points) + 1;
                ArrayResize(points, newSize);
                points[newSize - 1] = pt;

                lastValleyIndex = i;  // 谷のインデックスを更新
            }
        }
    }
};
