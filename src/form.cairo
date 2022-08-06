%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_not_equal,
    assert_nn,
    assert_le,
    assert_lt,
    assert_in_range,
)

#
# Constants
#

const STATUS_OPEN = 'OPEN'
const STATUS_READY = 'READY'
const STATUS_CLOSE = 'CLOSE'

#
# Events
#

@event
func FormCreated(id_form: felt):
end

@event
func SendPoint(id_form: felt, point: felt):
end

#
# Struct
#

struct Form:
    member name: felt
    member created_at: felt
    member status: felt
end

struct Question:
    member description: felt
    member optionA: felt
    member optionB: felt
    member optionC: felt
    member optionD: felt
    member optionCorrect: felt
end

struct QuestionDto:
    member description: felt
    member optionA: felt
    member optionB: felt
    member optionC: felt
    member optionD: felt
end

struct Row:
    member user: felt
    member score: felt
end

#
# Storage
#

### FORM ###

#lista de form
@storage_var
func forms(id_form: felt) -> (form: Form):
end

#cantidad de form
@storage_var
func forms_count() -> (count: felt):
end

### QUESTION ###

#lista de preguntas
@storage_var
func questions(id_form: felt, id_question: felt) -> (question: Question):
end

#cantidad de preguntas por form
@storage_var
func questions_count(id_form: felt) -> (questions_count: felt):
end

#respuestas correctas por form / de uso interno
@storage_var
func correct_form_answers(id_form: felt, id_question: felt) -> (correct_form_answer: felt):
end

### USERS ###

# respuesta nro por form / forma de obtener la lista de usuarios por form
@storage_var
func users_form(id_form: felt, id_answer: felt) -> (user: felt):
end

#cantidad de usuarios por form
@storage_var
func count_users_form(id_form: felt) -> (count_users: felt):
end

#usuarios que hicieron el form / boolean
@storage_var
func check_users_form(user_address: felt, id_form: felt) -> (bool: felt):
end

#puntos de un usuario por form
@storage_var
func points_users_form(user_address: felt, id_form: felt) -> (points: felt):
end

#respuestas de un usuario por form
@storage_var
func answer_users_form(user_address: felt, id_form: felt, id_question : felt) -> (
    answer : felt
):
end

#
# Modifier
#

#
# Getters
#

@view
func view_form{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form: felt
) -> (form: Form):
    let (res: Form) = forms.read(id_form)
    return (res)
end

@view
func view_form_count{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    count : felt
):
    let (count) = forms_count.read()
    return (count)
end

@view
func view_questions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt
) -> (records_len : felt, records : QuestionDto*):
    alloc_locals

    let (records : QuestionDto*) = alloc()
    let (count_question) = questions_count.read(id_form)
    _recurse_view_solution_records(id_form, count_question, records, 0)

    return (count_question, records)
end

@view
func view_question_count{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt
) -> (question_count : felt):
    let (count) = questions_count.read(id_form)
    return (count)
end

@view
func view_users_form_count{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt
) -> (count_user : felt):

    let (count) = count_users_form.read(id_form)
    return (count)
end

@view
func view_score_form{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt
) -> (records_len : felt, records : Row*):
    alloc_locals

    # let (records : (felt, felt)*) = alloc()
    let (records : Row*) = alloc()
    let (count) = count_users_form.read(id_form)
    _recurse_view_answers_records(id_form, count, records, 0)

    return (count, records)
end

#
# Externals
#

@external
func create_form{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt
) -> (id_form: felt):
    #create form
    alloc_locals
    let (local id_form) = _create_form(name)
    FormCreated.emit(id_form)
    return (id_form)
end

@external
func create_form_add_questions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt,
    dquestions_len : felt,
    dquestions : Question*,
    status_open : felt
) -> (id_form: felt):
    #create form
    alloc_locals

    let (local id_form) = _create_form(name)

    #add questions
    _add_questions(id_form, dquestions_len, dquestions)

    # close form
    if status_open == 0:
        _change_status_ready_form(id_form, name)
    end

    FormCreated.emit(id_form)
    return (id_form)
end

@external
func add_questions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt,
    dquestions_len : felt,
    dquestions : Question*,
    status_open : felt
) -> ():
    #create form
    alloc_locals

    #add questions
    _add_questions(id_form, dquestions_len, dquestions)
    
    # close form
    if status_open == 0:
        let (form: Form) = forms.read(id_form)
        _change_status_ready_form(id_form, form.name)
    end

    FormCreated.emit(id_form)
    return ()
end

@external
func send_answer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt, answers_len : felt, answers : felt*
) -> ():
    alloc_locals

    let (count) = forms_count.read()
    with_attr error_message("Form not found"):
        assert_in_range(id_form + 1 , 0, count +1)
    end

    let (count_question) = questions_count.read(id_form)
    with_attr error_message("Length of answers must be equal to the number of questions"):
        assert answers_len = count_question
    end

    let (caller_address) = get_caller_address()
    let (bool) = check_users_form.read(caller_address, id_form)
    with_attr error_message("You have already answered this form"):
        assert bool = FALSE
    end
    
    let (point) = _recurse_add_answers(id_form, count_question, answers, 0)

    points_users_form.write(caller_address, id_form, point)
    check_users_form.write(caller_address, id_form, TRUE)
    
    let (count_users) = count_users_form.read(id_form)
    users_form.write(id_form, count_users, caller_address)
    count_users_form.write(id_form, count_users + 1)

    SendPoint.emit(id_form, point) 
    return ()
end

#
# Internal
#

func _create_form{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    name: felt
) -> (id_form : felt):

    let (id_form) = forms_count.read()
    let (caller_address) = get_caller_address()
    forms.write(id_form, Form(name, caller_address, STATUS_OPEN))
    forms_count.write(id_form + 1)
    return (id_form)
end

func _change_status_ready_form{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    id_form: felt, 
    name: felt
) -> ():
    let (caller_address) = get_caller_address()
    forms.write(id_form, Form(name, caller_address, STATUS_READY))
    return ()
end

func  _change_status_close_form{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    id_form: felt, 
    name: felt
) -> ():
    let (caller_address) = get_caller_address()
    forms.write(id_form, Form(name, caller_address, STATUS_CLOSE))
    return ()
end

func _add_questions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt,
    dquestions_len: felt,
    dquestions : Question*
) -> ():
    alloc_locals
    #len > 0
    assert_le(0, dquestions_len)

    let (count_question) = questions_count.read(id_form)
    _add_a_questions(id_form, count_question, dquestions_len, dquestions)

    questions_count.write(id_form, count_question + dquestions_len)

    return ()
end



func _recurse_view_solution_records{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(id_form : felt, len : felt, arr : QuestionDto*, idx : felt) -> ():
    if idx == len:
        return ()
    end

    let (record : Question) = questions.read(id_form, idx)
    assert arr[idx] = QuestionDto(record.description, record.optionA, record.optionB, record.optionC, record.optionD)

    _recurse_view_solution_records(id_form, len, arr, idx + 1)
    return ()
end


func _recurse_view_answers_records{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(id_form : felt, len : felt, arr : Row*, idx : felt) -> ():
    if idx == len:
        return ()
    end

    let (user: felt) = users_form.read(id_form, idx)
    let (point) = points_users_form.read(user, id_form)
    assert arr[idx] = Row(user, point)

    _recurse_view_answers_records(id_form, len, arr, idx + 1)
    return ()
end

func _recurse_add_answers{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt, len : felt, arr : felt*, idx : felt
) -> (points : felt):
    alloc_locals
    if len == 0:
        return (0)
    end

    let (answer_correct) = correct_form_answers.read(id_form, idx)

    tempvar answer_user : felt
    answer_user = cast([arr], felt)
    # 0 >= answer <= 3
    assert_in_range(answer_user, 0, 4)
    let (caller_address) = get_caller_address()
    answer_users_form.write(caller_address, id_form, idx, answer_user)

    local t
    if answer_user == answer_correct:
        t = 5
    else:
        t = 0
    end
    let (local total) = _recurse_add_answers(id_form, len - 1, arr + 1, idx + 1)
    let res = t + total
    return (res)
end

func _get_answer_for_id{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    question : Question, id_answer : felt
) -> (correct_answer : felt):
    tempvar answer_user : felt
    if id_answer == 0:
        answer_user = question.optionA
    end
    if id_answer == 1:
        answer_user = question.optionB
    end
    if id_answer == 2:
        answer_user = question.optionC
    end
    if id_answer == 3:
        answer_user = question.optionD
    end
    return (answer_user)
end

func _add_a_questions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id_form : felt,
    id_question : felt,
    dquestions_len: felt,
    dquestions : Question*
) -> ():
    if dquestions_len == 0:
        return ()
    end

    let description = [dquestions].description
    let optionA = [dquestions].optionA
    let optionB = [dquestions].optionB
    let optionC = [dquestions].optionC
    let optionD = [dquestions].optionD
    let optionCorrect = [dquestions].optionCorrect
    
    with_attr error_message("Option correct must be between 0 and 3"):
        assert_in_range(optionCorrect, 0, 4)
    end

    correct_form_answers.write(id_form, id_question, optionCorrect)

    questions.write(
        id_form,
        id_question,
        Question(
        description,
        optionA,
        optionB,
        optionC,
        optionD,
        optionCorrect
        )
    )

    _add_a_questions(id_form, id_question + 1, dquestions_len - 1, dquestions + Question.SIZE)
    return ()
end