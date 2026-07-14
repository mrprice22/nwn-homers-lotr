// Hobbit Post (roadmap: hobbit-post)
// StartingConditional on Posco's daily offer entry: always TRUE (the
// done-today and still-carrying branches are checked first in the dialogue).
// Sets tokens 6340/6341 to today's addressee for the offer text.
#include "q_post_inc"

int StartingConditional()
{
    int nToday = QP_TodayIdx();
    SetCustomToken(6340, QP_Name(nToday));
    SetCustomToken(6341, QP_Place(nToday));
    return TRUE;
}
