//::///////////////////////////////////////////////
//:: mw_quiz_data -- MeaningWave guide quiz question banks.
//::
//:: 20 questions per guide. The engine (mw_quiz_inc) draws 5 at random with
//:: no repeats and shuffles the four answer choices into random display slots.
//::
//:: Each question is one packed row:
//::     "QUESTION~RIGHT~WRONG1~WRONG2~WRONG3"
//:: Field 0 is the prompt, field 1 is the SINGLE correct answer, fields 2-4 are
//:: distractors. The '~' is a reserved delimiter -- never use it in text. Avoid
//:: non-ASCII (em-dashes etc.) in these literals; use plain hyphens.
//::
//:: This file is the source of truth for the banks. The human-readable answer
//:: key in MeaningWave.md mirrors it, and tests/check_mw_quiz.py gates that each
//:: guide has exactly 20 well-formed rows. Grounded in each figure's real work
//:: (see the "Further reading" rows in docs.manual/MeaningWave.html).
//:://////////////////////////////////////////////

const int MW_BANK_SIZE = 20;

int MW_QCount(string sGuide) { return MW_BANK_SIZE; }

// ------------------------------------------------------------------ Jocko
// Extreme Ownership (Willink/Babin), Discipline Equals Freedom, Jocko Podcast.
string MW_JocRow(int i)
{
    switch (i)
    {
        case 0:  return "Complete the maxim: 'Discipline equals ___.'~Freedom.~Misery.~Obedience.~Comfort.";
        case 1:  return "Whose fault is it when the mission fails?~Mine. Extreme ownership.~The team's.~Circumstance.~The enemy's.";
        case 2:  return "Jocko gets bad news. What single word does he answer with?~Good.~Why me?~Retreat.~Unfair.";
        case 3:  return "What does Jocko recommend doing the moment the alarm sounds?~Get up immediately, no snooze.~Snooze once.~Sleep until rested.~Check your phone.";
        case 4:  return "You do not feel like doing the work. What do you do?~Do it anyway; the wanting follows the doing.~Wait to feel ready.~Find an easier path.~Rest first.";
        case 5:  return "In Extreme Ownership, who is ultimately responsible for a team's performance?~The leader.~The lowest performer.~Higher command.~No one.";
        case 6:  return "What does Jocko mean by 'Default: Aggressive'?~Lean into problems and act decisively.~Attack every person you meet.~Never plan ahead.~Always retreat to safety.";
        case 7:  return "What is the 'dichotomy of leadership'?~Balancing opposing qualities, like leading and following.~Choosing chaos over order.~Ranking soldiers by strength.~Never compromising.";
        case 8:  return "The combat principle 'Cover and Move' means what?~Teams support each other toward the goal.~Hide and never advance.~Every man for himself.~Abandon the wounded.";
        case 9:  return "What does Jocko say about a plan's complexity?~Keep it simple so everyone can execute under stress.~Make it as detailed as possible.~Plans are useless.~Only the leader needs the plan.";
        case 10: return "'Prioritize and Execute' tells a leader to do what?~Handle the highest-priority problem first, then the next.~Do everything at once.~Delegate everything.~Wait for orders.";
        case 11: return "What is the relationship between discipline and freedom, per Jocko?~Discipline creates freedom.~Discipline destroys freedom.~Freedom needs no discipline.~They are unrelated.";
        case 12: return "What is the title of Jocko's first book, co-written with Leif Babin?~Extreme Ownership.~The Way of the SEAL.~Discipline Equals Freedom.~Can't Hurt Me.";
        case 13: return "In which branch of the U.S. military did Jocko serve?~The Navy, in the SEAL Teams.~The Army.~The Marines.~The Air Force.";
        case 14: return "When a subordinate makes a mistake, extreme ownership says the leader first asks what?~How did I fail to lead them?~Who do I blame?~How do I punish them?~Why are they weak?";
        case 15: return "What does Jocko say about excuses?~Own the outcome; there are no excuses.~A good excuse ends the matter.~Excuses protect the team.~Blame the circumstance.";
        case 16: return "The disciplined mind treats a hard task as what?~An opportunity to get better.~A punishment to avoid.~Someone else's job.~A reason to quit.";
        case 17: return "What does Jocko say a leader must do to see the whole battlefield?~Detach, step back, and assess.~Charge in blindly.~Follow the crowd.~Wait to be told.";
        case 18: return "Extreme ownership points blame in which direction first?~Inward, toward yourself.~Downward, to subordinates.~Outward, to circumstance.~Upward only.";
        case 19: return "What is Jocko's counsel when you feel overwhelmed by problems?~Prioritize, then execute one at a time.~Freeze and wait.~Quit the mission.~Do them all at once.";
    }
    return "";
}

// ------------------------------------------------------------------ Peterson
// 12 Rules for Life, Maps of Meaning.
string MW_PetRow(int i)
{
    switch (i)
    {
        case 0:  return "What is Rule 1 of 12 Rules for Life?~Stand up straight with your shoulders back.~Tell the truth.~Set your house in order.~Pet a cat.";
        case 1:  return "What is responsibility, in Peterson's view?~The path to meaning, freely chosen.~A burden imposed by tyrants.~A trick to enslave the strong.~An illusion.";
        case 2:  return "Rule 4 says compare yourself to whom?~Who you were yesterday, not who someone else is today.~The most successful person you know.~No one at all.~Your parents.";
        case 3:  return "What 'dragon' must the individual confront?~The chaos within oneself.~The taxman.~A literal beast.~Your neighbour.";
        case 4:  return "Rule 6 says do what before criticising the world?~Set your house in perfect order.~Overthrow the government.~Read more books.~Blame your parents.";
        case 5:  return "Rule 8 concerns what?~Telling the truth, or at least not lying.~Standing up straight.~Petting cats.~Cleaning your room.";
        case 6:  return "What does Peterson say about hierarchies of competence?~They are ancient, not merely social constructs.~They are always corrupt and must be destroyed.~Lobsters invented them.~They should be ignored.";
        case 7:  return "Rule 7 tells you to pursue what?~What is meaningful, not what is expedient.~What is easy.~What others expect.~Wealth above all.";
        case 8:  return "Peterson cites which animal to argue hierarchy is deep in biology?~The lobster.~The wolf.~The chimpanzee.~The eagle.";
        case 9:  return "What is the title of Peterson's dense first book on myth and meaning?~Maps of Meaning.~12 Rules for Life.~Beyond Order.~The Gulag Archipelago.";
        case 10: return "Rule 2 says to treat yourself like whom?~Someone you are responsible for helping.~A worthless failure.~A king above others.~A stranger.";
        case 11: return "Where is meaning found, for Peterson?~At the border between order and chaos.~In pure order.~In pure chaos.~In wealth.";
        case 12: return "Rule 9 advises you to assume the person you're listening to might what?~Know something you don't.~Be lying to you.~Be beneath you.~Waste your time.";
        case 13: return "Whose account of the Gulag shaped Peterson's warnings about ideology?~Aleksandr Solzhenitsyn.~Karl Marx.~Friedrich Nietzsche.~Sigmund Freud.";
        case 14: return "Rule 10 is about being precise in what?~Your speech.~Your diet.~Your finances.~Your posture.";
        case 15: return "Peterson says the antidote to chaos begins with what small act?~Setting your own life, and room, in order.~Winning an argument.~Quitting your job.~Blaming society.";
        case 16: return "What does Peterson mean by 'the tragedy of Being'?~Suffering is inherent, yet can be borne with meaning.~Life is meaningless.~Suffering can be eliminated.~Only the weak suffer.";
        case 17: return "Rule 3 advises making friends with people who do what?~Want the best for you.~Flatter you constantly.~Envy your success.~Ask nothing of you.";
        case 18: return "Peterson frames the ideal as balancing which two forces?~Order and chaos.~Good and evil spirits.~Wealth and poverty.~Past and future.";
        case 19: return "'Compare yourself to who you were yesterday' guards against what?~Envy and unfair comparison to others.~Ambition of any kind.~Self-improvement.~Telling the truth.";
    }
    return "";
}

// ------------------------------------------------------------------ Watts
// The Book, The Way of Zen, The Wisdom of Insecurity.
string MW_WatRow(int i)
{
    switch (i)
    {
        case 0:  return "Who is doing the experiencing, according to Watts?~There is no separate experiencer apart from the experience.~A soul sealed in the skull.~A self standing outside the world.~No one at all.";
        case 1:  return "In The Book, what is the taboo Watts says we are never told?~That you are the whole universe, not a separate ego.~That death is final.~That money is evil.~That desire is sin.";
        case 2:  return "What is the universe, in Watts's playful metaphor?~A game of hide-and-seek played by what we are.~A machine of dead matter.~A moral test set by God.~A meaningless accident.";
        case 3:  return "Why act at all, if the goal is incidental?~Because the doing is the play, like music or dance.~To defeat others.~To earn salvation.~To escape the body.";
        case 4:  return "Watts describes the self as more like which part of speech?~A verb, not a noun.~A noun.~An adjective.~A pronoun only.";
        case 5:  return "How do you truly let go, per Watts?~By yielding gracefully, not gripping harder.~By renouncing the body.~By force of will.~By seizing control.";
        case 6:  return "The Wisdom of Insecurity argues security is found where?~In accepting impermanence, not resisting it.~In wealth and safety.~In rigid belief.~In controlling the future.";
        case 7:  return "Which Eastern traditions did Watts popularise in the West?~Zen Buddhism and Taoism.~Sunni Islam and Sufism.~Calvinism.~Jainism only.";
        case 8:  return "The Taoist idea of 'wu wei' means what?~Effortless action, going with the grain of things.~Constant striving.~Total inaction and sloth.~Aggressive conquest.";
        case 9:  return "Watts says the ego is best understood as what?~A useful illusion, a social convention.~Your eternal true soul.~A demon to be exorcised.~The seat of reason only.";
        case 10: return "Chasing pleasure directly, Watts warns, tends to do what?~Destroy the very pleasure sought.~Guarantee happiness.~Please the gods.~Build character.";
        case 11: return "What did Watts call the belief that we are skin-encapsulated egos?~An illusion of separateness.~The highest truth.~Scientific fact.~Divine law.";
        case 12: return "In Zen, 'satori' refers to what?~A sudden flash of awakening.~A long punishment.~A written scripture.~A meditation posture.";
        case 13: return "Watts compares life to music to make what point?~The point is the playing, not reaching the end.~Only the finale matters.~Life should be efficient.~Silence is superior.";
        case 14: return "The symbol of yin and yang expresses what?~Opposites are interdependent, not at war.~Good must destroy evil.~Matter is an illusion.~Order defeats chaos.";
        case 15: return "What was Watts trained as before turning to Zen?~An Anglican, then Episcopal, priest.~A physicist.~A soldier.~A lawyer.";
        case 16: return "'You are the universe experiencing itself' expresses which idea?~Nonduality; self and cosmos are not separate.~Solipsism, only you exist.~Materialism.~Predestination.";
        case 17: return "What does Watts say about the present moment?~It is the only place life actually happens.~It is an illusion.~It must be sacrificed for the future.~It cannot be experienced.";
        case 18: return "In the Tao, how does the sage act toward nature?~Flows with it rather than forcing against it.~Conquers and tames it.~Ignores it entirely.~Fears it.";
        case 19: return "Watts's overall message about the cosmos is best described as what?~Playful and interconnected, not grim and separate.~Cold and mechanical.~A courtroom of judgment.~An accident to endure.";
    }
    return "";
}

// ------------------------------------------------------------------ Campbell
// The Hero with a Thousand Faces, The Power of Myth; the monomyth.
string MW_CamRow(int i)
{
    switch (i)
    {
        case 0:  return "What is the first stage of the hero's journey?~The Call to Adventure.~The Return.~The Apotheosis.~The Reward.";
        case 1:  return "What is the role of the threshold guardian?~To test whether the hero is worthy to cross.~To kill all who approach.~To guide the hero home.~To grant wishes.";
        case 2:  return "Why must the hero descend into the abyss?~To die to the old self and be reborn.~To collect gold.~To impress onlookers.~To avoid danger.";
        case 3:  return "What famous advice did Campbell give for living?~Follow your bliss.~Obey the law.~Seek wealth.~Trust no one.";
        case 4:  return "What does the hero bring back at the journey's end?~A boon to benefit the community.~Conquest and spoils.~Nothing.~Personal fame only.";
        case 5:  return "Campbell's word for the single myth underlying all cultures is what?~The monomyth.~The parable.~The allegory.~The epic.";
        case 6:  return "What is the title of Campbell's landmark 1949 book?~The Hero with a Thousand Faces.~The Golden Bough.~The Power of Myth.~The Masks of God.";
        case 7:  return "Which filmmaker credited Campbell as an influence on Star Wars?~George Lucas.~Steven Spielberg.~Stanley Kubrick.~Ridley Scott.";
        case 8:  return "The stage of 'supernatural aid' often involves what figure?~A mentor or wise helper.~A tax collector.~A rival king.~A merchant.";
        case 9:  return "'Refusal of the Call' describes what?~The hero's initial hesitation to begin.~The hero's death.~The final victory.~The mentor's betrayal.";
        case 10: return "Campbell's three broad phases are Departure, Initiation, and what?~Return.~Conquest.~Judgment.~Rest.";
        case 11: return "The 'belly of the whale' symbolises what?~The hero passing into transformation.~A literal sea voyage.~The reward.~The ordinary world.";
        case 12: return "In Campbell's view, myths function to do what?~Give life meaning and orient the psyche.~Record accurate history.~Entertain children only.~Predict the future.";
        case 13: return "Who was Campbell's collaborator in the PBS series The Power of Myth?~Bill Moyers.~Carl Sagan.~Joseph Pulitzer.~Alan Watts.";
        case 14: return "'Meeting with the goddess' and 'atonement with the father' belong to which phase?~Initiation.~Departure.~Return.~Refusal.";
        case 15: return "Campbell drew heavily on which psychologist's idea of archetypes?~Carl Jung.~Sigmund Freud.~B.F. Skinner.~William James.";
        case 16: return "What does 'follow your bliss' actually urge?~Pursue your deepest calling even at a cost.~Chase easy pleasure.~Avoid all risk.~Obey tradition.";
        case 17: return "The hero's journey ultimately serves whom?~The community, through the boon returned.~Only the hero.~The gods alone.~No one.";
        case 18: return "The 'ultimate boon' is best described as what?~The goal achieved that can renew the world.~A pile of treasure.~A weapon.~A throne.";
        case 19: return "Campbell taught comparative mythology for decades at which college?~Sarah Lawrence College.~Harvard.~Oxford.~Yale.";
    }
    return "";
}

// ------------------------------------------------------------------ McKenna
// Food of the Gods, The Archaic Revival; timewave, the Other, 'felt presence'.
string MW_MckRow(int i)
{
    switch (i)
    {
        case 0:  return "Culture is best described by McKenna as what?~Your operating system.~An adornment.~A prison to smash.~An illusion.";
        case 1:  return "Complete McKenna's phrase: 'the felt presence of ___.'~immediate experience.~ancient gods.~future novelty.~the timewave.";
        case 2:  return "What is McKenna's 'timewave'?~A fractal model of novelty increasing over time.~A strictly linear calendar.~A tidal chart.~A memory illusion.";
        case 3:  return "How did McKenna describe 'the Other' met in visions?~Closer to you than your own breath.~A distant stranger.~Purely nonexistent.~A hostile enemy.";
        case 4:  return "McKenna described language as what kind of thing?~An almost living organism that wants to be shared.~Mere communication.~A useless trick.~A prison only.";
        case 5:  return "What is the thesis of McKenna's 'Stoned Ape' hypothesis?~Psilocybin catalysed human cognitive evolution.~Apes never changed.~Fire alone made us human.~Language came from writing.";
        case 6:  return "What is the title of McKenna's book on drugs and human history?~Food of the Gods.~The Archaic Revival.~True Hallucinations.~The Doors of Perception.";
        case 7:  return "McKenna urged a 'return' to what?~The archaic, shamanic ways of direct experience.~Pure rationalism.~Industrial progress.~Strict tradition.";
        case 8:  return "What did McKenna mean by 'novelty'?~The increase of complexity and connection in the universe.~Boredom.~Random noise.~Simple repetition.";
        case 9:  return "McKenna's brother and frequent collaborator was named what?~Dennis McKenna.~Terence Jr.~Aldous.~Gordon.";
        case 10: return "McKenna urged us to trust what as a teacher?~Nature and the plants.~Only governments.~Only machines.~No experience at all.";
        case 11: return "'The syntactic prison' refers to what?~Being trapped inside habitual language and thought.~An actual jail.~Grammar textbooks.~A computer program.";
        case 12: return "'Boundary dissolution' describes what?~The felt merging of self and world in deep states.~Building stronger walls.~A legal ruling.~Physical death.";
        case 13: return "What did McKenna claim about the imagination?~It is a real ground of being to be explored.~It is worthless.~It is dangerous and must be suppressed.~It does not exist.";
        case 14: return "Which field did McKenna work in?~The study of psychoactive plants and shamanism.~Nuclear physics.~Corporate law.~Marine biology.";
        case 15: return "McKenna saw history as accelerating toward what?~A concrescence of novelty.~Total stasis.~Simple decay.~Endless repetition.";
        case 16: return "What was McKenna's stance toward blind belief?~Reject dogma; value direct experience.~Accept all authority.~Believe nothing ever.~Follow one guru.";
        case 17: return "McKenna held that real insight often comes how?~Through direct, sometimes psychedelic, experience.~Through obedience.~Through wealth.~Through avoidance.";
        case 18: return "McKenna saw the psychedelic experience primarily as what?~A doorway to meaning and the imagination.~Mere entertainment.~A medical error.~A punishment.";
        case 19: return "McKenna's tone about the future was generally what?~Hopeful about a coming shift in consciousness.~Nihilistic despair.~Total indifference.~Fear of all change.";
    }
    return "";
}

// ------------------------------------------------------------------ Jung
// Shadow, individuation, persona, collective unconscious, archetypes.
string MW_JunRow(int i)
{
    switch (i)
    {
        case 0:  return "What is the shadow, in Jungian terms?~The disowned parts of yourself, neither simply good nor evil.~The literal devil.~Pure evil to be destroyed.~Your reflection.";
        case 1:  return "How does one become psychologically whole?~By integrating the shadow, not denying it.~By denying the shadow.~By becoming perfectly pure.~By ignoring the unconscious.";
        case 2:  return "What is individuation?~Becoming the totality of who you truly are.~Selfishness.~Total solitude.~Conformity to society.";
        case 3:  return "What lives in the collective unconscious?~Inherited archetypes shared by all humanity.~Nothing of importance.~Only demons.~Personal memories only.";
        case 4:  return "What is the persona?~The social mask we wear; useful, but not our true self.~Our deepest true self.~A lie to be destroyed.~A mental illness.";
        case 5:  return "Jung's term for universal, inherited images and patterns is what?~Archetypes.~Complexes.~Reflexes.~Instincts only.";
        case 6:  return "What does the 'anima' refer to in Jung's model?~The inner feminine within a man's psyche.~An external spirit.~A dream symbol only.~A neurosis.";
        case 7:  return "What did Jung call meaningful coincidence?~Synchronicity.~Causality.~Projection.~Sublimation.";
        case 8:  return "Jung broke from which former mentor over theory?~Sigmund Freud.~Alfred Adler.~William James.~B.F. Skinner.";
        case 9:  return "What is the 'Self', with a capital S, in Jung's thought?~The unifying centre of the whole psyche.~The ego alone.~The body.~The persona.";
        case 10: return "What happens when the shadow is repressed and unowned?~It is projected onto others and acted out.~It simply disappears.~It becomes the persona.~It strengthens the ego healthily.";
        case 11: return "What is the name of Jung's book of confrontations with his own unconscious?~The Red Book (Liber Novus).~The Interpretation of Dreams.~Man and His Symbols.~The Ego and the Id.";
        case 12: return "Dreams, for Jung, primarily serve to do what?~Compensate and communicate from the unconscious.~Predict the lottery.~Mean nothing at all.~Only replay the day.";
        case 13: return "The 'wise old man' and 'the great mother' are examples of what?~Archetypes.~Personas.~Complexes.~Neuroses.";
        case 14: return "What is a 'complex' in Jungian psychology?~An emotionally charged cluster of associations.~A building.~A rational argument.~A persona.";
        case 15: return "Jung believed the second half of life should focus on what?~Meaning, individuation, and the inner world.~Accumulating wealth.~Social climbing.~Nothing in particular.";
        case 16: return "What does the 'animus' refer to?~The inner masculine within a woman's psyche.~A group of enemies.~A dream demon.~The persona.";
        case 17: return "Jung saw religious symbols as what?~Expressions of deep psychic realities.~Pure superstition to discard.~Literal history.~Meaningless.";
        case 18: return "Confronting the shadow typically feels how, at first?~Uncomfortable, even shameful.~Effortless and pleasant.~Completely neutral.~Physically painful only.";
        case 19: return "The goal of Jungian analysis is best described as what?~Integration of the psyche toward wholeness.~Elimination of all emotion.~Perfect happiness forever.~Erasing the unconscious.";
    }
    return "";
}

// ------------------------------------------------------------------ Aurelius
// Meditations; Stoicism.
string MW_AurRow(int i)
{
    switch (i)
    {
        case 0:  return "What is truly in your power, per Aurelius?~Your judgements, intentions, and reactions.~Everything you want.~Other people's actions.~The future.";
        case 1:  return "Complete the Stoic maxim: 'The obstacle is ___.'~the way.~to be avoided.~a punishment.~meaningless.";
        case 2:  return "What does 'memento mori' mean?~Remember that you will die.~Remember the dead.~Remember the dawn.~Remember to rest.";
        case 3:  return "The soul, Aurelius writes, is dyed by what?~The colour of its thoughts.~Its birth.~The body.~Fortune.";
        case 4:  return "How should one begin each day, per Meditations?~Expecting to meet the ungrateful and cruel, unharmed within.~Expecting only joy.~Expecting the gods to provide.~Expecting wealth.";
        case 5:  return "Aurelius was emperor of which realm?~Rome.~Greece.~Persia.~Egypt.";
        case 6:  return "To which school of philosophy did Aurelius belong?~Stoicism.~Epicureanism.~Cynicism.~Skepticism.";
        case 7:  return "For whom was Meditations originally written?~Himself, as private notes.~The Roman Senate.~His son.~The public.";
        case 8:  return "The Stoics divide things into which two categories?~What is up to us and what is not.~Good and evil people.~Rich and poor.~Body and gods.";
        case 9:  return "What should we do about things outside our control, per the Stoics?~Accept them calmly.~Rage against them.~Fear them.~Neglect all duty.";
        case 10: return "Aurelius often reminds himself that all things are what?~Impermanent and soon forgotten.~Eternal.~Under his command.~Meaningless jokes.";
        case 11: return "What is the Stoic view of virtue?~It is the only true good.~It is worthless.~It is one good among riches.~It is unattainable.";
        case 12: return "When wronged, Aurelius counsels what response?~Return to reason; refuse to be harmed by another's fault.~Immediate revenge.~Despair.~Public complaint.";
        case 13: return "Complete the thought: 'The best revenge is ___.'~to not be like your enemy.~swift retaliation.~to grow rich.~to forget nothing.";
        case 14: return "Aurelius reminds himself to act for what?~The common good, the good of the whole.~His own glory.~Wealth.~Comfort.";
        case 15: return "The Stoic idea of 'amor fati' means what?~Love of one's fate; embracing what happens.~Hatred of destiny.~Fear of death.~Love of money.";
        case 16: return "What does Aurelius say about complaining and blame?~Waste no time on it; do the work before you.~Blame the gods.~Blame others freely.~Complaint is a virtue.";
        case 17: return "Reason, the 'ruling faculty', should govern what?~Our impulses and reactions.~Only our finances.~Other people.~The weather.";
        case 18: return "Aurelius pictures the cosmos as what?~An ordered, interconnected whole.~Random chaos.~A cruel joke.~A machine of despair.";
        case 19: return "The Stoic sage remains what amid fortune's changes?~Tranquil and steadfast.~Anxious.~Greedy.~Vengeful.";
    }
    return "";
}

// Dispatch: return the packed row for guide sGuide, question index i (0-based).
string MW_QRow(string sGuide, int i)
{
    if (sGuide == "jocko")    return MW_JocRow(i);
    if (sGuide == "peterson") return MW_PetRow(i);
    if (sGuide == "watts")    return MW_WatRow(i);
    if (sGuide == "campbell") return MW_CamRow(i);
    if (sGuide == "mckenna")  return MW_MckRow(i);
    if (sGuide == "jung")     return MW_JunRow(i);
    if (sGuide == "aurelius") return MW_AurRow(i);
    return "";
}
