// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

//import './Utility.sol';
import './Airline.sol';

contract Ticket {
    address customerAddress;
    address airlineAddress;
    string flightID;
    string bookingReferenceID;
    uint numberofSeats;
    uint ticketFare;
    uint scheduledDeparture;
    uint actualDeparture;
    uint ticketStatus;
    uint penaltyCount = 0;
    uint delayPenalty1_PerBelow_4H = 20; // Can be set at the time of booking or can vary based on the ticket category, but for this project it is out of scope
    uint delayPenalty2_PerAbove_4H = 95; // Can be set at the time of booking or can vary based on the ticket category, but for this project it is out of scope

    enum TicketState{NotTravelled, OnTime, FlightDelay, FlightCancelled,Completed,CancelledByCustomer}
    event RevertEvent (
      string ErrorMessage
    );
    // Note, Ticket contract is generic and independant. Agnostic of the Airline or Aggregator  
    // This will create a new contract for the booking as requested by the Airline.
    // Need to be called by an existing Airline contract, this check is done with a simple authorisation by the airline.
    
    constructor (address _customer, string memory _flightId, string memory _breference,uint _seats, uint _transferValue, uint _scheduledDeparture, uint _actualDeparture,uint _flightStatus ){
        // check if Airline authorises this requested
        if (Airline(payable(msg.sender)).authoriseTicket() == false)
        {
            emit RevertEvent("This is not authorised request from an Airline");
            revert("This is not authorised request from an Airline");

        }
        customerAddress = _customer;
        flightID = _flightId;
        bookingReferenceID = _breference;
        numberofSeats = _seats;
        if(_flightStatus == 3){
            ticketStatus = uint(TicketState.FlightDelay);
        }
        else{
            ticketStatus = uint(TicketState.NotTravelled);
        }
        ticketFare = _transferValue;
        scheduledDeparture = _scheduledDeparture;
        actualDeparture = _actualDeparture;
    }
    function cancel(uint _penaltyPercentage) external returns(bool){
        // Ticket should not have current status in 'Completed', 'CancelledByCustomer', 'FlightCancelled'. 
        // This check to be removed once the flight statuses are working fine after the completed and cancelled action
        if (ticketStatus == uint(TicketState.Completed) || ticketStatus == uint(TicketState.CancelledByCustomer) || ticketStatus == uint(TicketState.FlightCancelled)){
            emit RevertEvent(string(abi.encodePacked("** Error **: Ticket is already in status status in Completed, CancelledByCustomer, FlightCancelled status",address(this))));
            revert(string(abi.encodePacked("** Error **: Ticket is already in status status in Completed, CancelledByCustomer, FlightCancelled status",address(this))));
        }
        // set the ticket status if eligible
        ticketStatus = uint(TicketState.CancelledByCustomer);
        address payable ticketAccount = payable(address(this));
        address payable customer = payable(customerAddress);
        //reduce the penalty amount and transfer to customer
        // GETH below work not in handled
        // uint transferAmountCustomer = getTicketBalance() - (getTicketBalance()*_penaltyPercentage/100);
        uint transferAmountCustomer = ticketAccount.balance - (ticketAccount.balance*_penaltyPercentage/100);
        customer.transfer(transferAmountCustomer);
        uint transferAmountAirline = ticketAccount.balance;
        //Remaining balance., that is the penalty amount to be transfered to airlines
        address payable airlineAccount = payable(msg.sender);
        airlineAccount.transfer(transferAmountAirline); 
        return true;
    }
    function updateActualDeparture(uint _actualDeparture) external returns(bool){
        if(scheduledDeparture == _actualDeparture){
            ticketStatus = uint(TicketState.OnTime);                
        }
        else{
            ticketStatus = uint(TicketState.FlightDelay);                
        }
        actualDeparture = _actualDeparture;
        return true;
    }   
    function completeJourney() external returns(bool){
        // Expected test pass: Ticket statuses Completed and Cancelled are to be updated correctly by Airline cancelFlight and completeFlight
        // So those conditions need not be checked again.
        if (ticketStatus != uint(TicketState.CancelledByCustomer) ){
            address payable airlineAccount = payable(msg.sender);
            address payable ticketAccount = payable(address(this));
            
            ticketStatus = uint(TicketState.Completed);
            airlineAccount.transfer(ticketAccount.balance); 
        }
        return true;
    }
    function cancelByAirline() external returns(bool){
        // Expected test pass: Ticket statuses Completed and Cancelled are to be updated correctly by Airline cancelFlight and completeFlight
        // So those conditions need not be checked again.
        if (ticketStatus != uint(TicketState.CancelledByCustomer)){
            ticketStatus = uint(TicketState.FlightCancelled);
            address payable receiver = payable(customerAddress);
            address payable ticketAccount = payable(address(this));
            receiver.transfer(ticketAccount.balance);
        }
        return true;
    }
    function delayRefund(uint _timeDifference) external returns(bool){
        // Expected test pass: Ticket statuses Completed and Cancelled are to be updated correctly by Airline cancelFlight and completeFlight
        // So those conditions need not be checked again.
        bool returnValue;
        uint refundAmount; 
        uint actualTimeDifference;
        address payable ticketAccount = payable(address(this));
        //Ticket in 'NotTravelled will have actualDeparture as 0, so initialise it to scheduledDeparture
        //Later add the time difference;  
        if(actualDeparture == 0) {
            actualDeparture = scheduledDeparture;
            actualTimeDifference = _timeDifference;
        }
        else{
            //This will take care of the subsequent multiple delays and also previously OnTime updated flights
            // The difference is = Total delay - previously updated delay, which need to be added to the actual departure time.
            actualTimeDifference = _timeDifference-(actualDeparture-scheduledDeparture);
        }
        uint cumulativeTimeDifference = _timeDifference;   
        if (ticketStatus == uint(TicketState.CancelledByCustomer)){
            returnValue = true;
        }
        else{ 
            if(penaltyCount != 1 && cumulativeTimeDifference <= 4 hours) {
                //Flight can have multiple delay updates.
                //Not all such updates qualify for penalty, unless accumulative delay  breaches the threshold
                refundAmount = ticketAccount.balance*delayPenalty1_PerBelow_4H/100;        
                ticketStatus = uint(TicketState.FlightDelay);
                penaltyCount = 1;
            }
            if(penaltyCount != 2 && cumulativeTimeDifference > 4 hours) {
                //If the first delay update itself is beyond this threshold .
                refundAmount = ticketAccount.balance*delayPenalty2_PerAbove_4H/100;        
                ticketStatus = uint(TicketState.FlightDelay);
                penaltyCount = 2;
            }
            
            address payable receiver = payable(customerAddress);
            actualDeparture = actualDeparture + actualTimeDifference;
            receiver.transfer(refundAmount);
            returnValue = true;
        }
        return returnValue;
    }

    // returns
    //address of the ticket, flight identifier, booking reference,  number of seats, scheduled departure (timestamp),actual departure (timestamp),status
    function getTicketDetails() external view returns(address,string memory,string memory, uint,uint,uint,uint,uint){
        return(address(this),flightID, bookingReferenceID, numberofSeats,ticketFare, scheduledDeparture, actualDeparture,ticketStatus);
     }
    // This function was used in other contracts as an encapsulated function, but works only for GETH and not HL 
    // function getTicketBalance() public view returns (uint) {
    //     return address(this).balance;
    // }
    function getTicketFlightID() public view returns (string memory) {
        return flightID;
    }
    function getTicketStatus() public view returns (uint) {
        return ticketStatus;
    }
    function getTicketAddress() external view returns(address){
        return address(this);
    }
    function getDepartureTime() external view returns(uint departureTime){
        departureTime = scheduledDeparture;
        if(actualDeparture > 0){
            departureTime = actualDeparture;
        }
        return departureTime;
    }
    function getSeats() external view returns(uint){
        return numberofSeats;
    }
    receive() external payable{
    }
    fallback() external payable{
    }
}
